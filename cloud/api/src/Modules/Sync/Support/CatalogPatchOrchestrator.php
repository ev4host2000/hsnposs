<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Support;

use MizaCloud\Modules\Sync\Contract\ChangeDetectionEngine;
use MizaCloud\Modules\Sync\Contract\FieldMetadataProvider;
use MizaCloud\Modules\Sync\Contract\PatchBuilder;
use MizaCloud\Modules\Sync\Contract\PatchValidator;

/**
 * Shared Update Contract v2 orchestrator (pure — no DB/HTTP).
 *
 * Resolves native patch or Full→Patch adapter, validates, runs CatalogVersionGate::decidePatch.
 */
final class CatalogPatchOrchestrator
{
    public function __construct(
        private readonly FieldMetadataProvider $metadata,
        private readonly ChangeDetectionEngine $detector,
        private readonly PatchBuilder $builder,
        private readonly PatchValidator $validator,
        private readonly CatalogFullToPatchAdapter $adapter,
    ) {
    }

    public function metadata(): FieldMetadataProvider
    {
        return $this->metadata;
    }

    public function detector(): ChangeDetectionEngine
    {
        return $this->detector;
    }

    public function builder(): PatchBuilder
    {
        return $this->builder;
    }

    public function validator(): PatchValidator
    {
        return $this->validator;
    }

    public function adapter(): CatalogFullToPatchAdapter
    {
        return $this->adapter;
    }

    /**
     * @param array<string, mixed> $event
     * @param array<string, mixed> $payloadJson
     * @param array<string, mixed> $serverRow dictionary-shaped authoritative row
     * @return array{
     *   decision: string,
     *   patch: array<string, mixed>,
     *   normalized_changed_fields: array<string, mixed>,
     *   new_row_version: int,
     *   errors: list<string>,
     *   source: 'native_patch'|'full_to_patch_adapter'
     * }
     */
    public function planUpdate(
        string $entityType,
        string $entityPath,
        string $entityId,
        string $operation,
        array $event,
        array $payloadJson,
        array $serverRow,
        int $clientRowVersion,
    ): array {
        $serverVersion = max(1, (int) ($serverRow['row_version'] ?? 1));
        $operationId = $this->resolveOperationId($event, $payloadJson);

        try {
            if (CatalogFullToPatchAdapter::isNativePatchEvent($operation, $event, $payloadJson)) {
                $patch = $this->buildNativePatch(
                    $entityType,
                    $entityId,
                    $event,
                    $payloadJson,
                    $operationId,
                );
                $source = 'native_patch';
            } else {
                $explicitBase = $this->readPositiveInt($event, 'base_row_version')
                    ?? $this->readPositiveInt($payloadJson, 'base_row_version');
                $baseForAdapter = $explicitBase ?? $serverVersion;
                $patch = $this->adapter->adapt(
                    $entityType,
                    $entityId,
                    $serverRow,
                    $payloadJson,
                    $operationId,
                    $baseForAdapter,
                );
                $source = 'full_to_patch_adapter';

                if ($explicitBase === null && $clientRowVersion < $serverVersion) {
                    $patch['base_row_version'] = max(1, $clientRowVersion);
                }
            }
        } catch (\InvalidArgumentException $e) {
            return [
                'decision' => 'validation_error',
                'patch' => [
                    'entity_type' => $entityType,
                    'entity_id' => $entityId,
                    'operation' => PatchBuilder::OPERATION_UPDATE,
                    'operation_id' => $operationId,
                    'base_row_version' => $serverVersion,
                    'dictionary_version' => $this->metadata->dictionaryVersion(),
                    'changed_fields' => [],
                    'is_no_op' => true,
                ],
                'normalized_changed_fields' => [],
                'new_row_version' => $serverVersion,
                'errors' => [$e->getMessage()],
                'source' => CatalogFullToPatchAdapter::isNativePatchEvent($operation, $event, $payloadJson)
                    ? 'native_patch'
                    : 'full_to_patch_adapter',
            ];
        }

        $validation = $this->validator->validate($patch, $entityPath);
        if ($validation['status'] !== PatchValidator::RESULT_VALID) {
            return [
                'decision' => 'validation_error',
                'patch' => $patch,
                'normalized_changed_fields' => [],
                'new_row_version' => $serverVersion,
                'errors' => $validation['errors'],
                'source' => $source,
            ];
        }

        /** @var array<string, mixed> $normalized */
        $normalized = $validation['normalized_changed_fields'] ?? [];

        $baseSnap = $this->adapter->snapshotFromServerRow($entityType, $serverRow);
        $effectiveChanges = [];
        foreach ($normalized as $name => $value) {
            $field = $this->metadata->field($entityType, $name);
            $serverVal = array_key_exists($name, $baseSnap)
                ? $this->detector->normalize($field, $baseSnap[$name])
                : $this->detector->normalize($field, $field->defaultValue);
            if (!$this->detector->valuesEqual($field, $serverVal, $value)) {
                $effectiveChanges[$name] = $value;
            }
        }

        $baseRowVersion = (int) $patch['base_row_version'];
        $decision = CatalogVersionGate::decidePatch(
            $serverVersion,
            $baseRowVersion,
            $effectiveChanges === [],
        );

        return [
            'decision' => $decision,
            'patch' => $patch,
            'normalized_changed_fields' => $effectiveChanges,
            'new_row_version' => $decision === CatalogVersionGate::DECISION_APPLY
                ? $serverVersion + 1
                : $serverVersion,
            'errors' => [],
            'source' => $source,
        ];
    }

    /**
     * @param array<string, mixed> $event
     * @param array<string, mixed> $payloadJson
     * @return array<string, mixed>
     */
    private function buildNativePatch(
        string $entityType,
        string $entityId,
        array $event,
        array $payloadJson,
        string $operationId,
    ): array {
        $changed = $event['changed_fields'] ?? $payloadJson['changed_fields'] ?? null;
        if (!is_array($changed)) {
            throw new \InvalidArgumentException('Native patch requires changed_fields');
        }

        $changedMap = [];
        $isList = array_is_list($changed);
        if ($isList) {
            foreach ($changed as $name) {
                if (!is_string($name) || $name === '') {
                    throw new \InvalidArgumentException('changed_fields list entries must be non-empty strings');
                }
                if (!array_key_exists($name, $payloadJson)) {
                    throw new \InvalidArgumentException('payload_json missing value for changed field: ' . $name);
                }
                $changedMap[$name] = $payloadJson[$name];
            }
            $this->assertPayloadOnlyChangedFields($payloadJson, array_keys($changedMap));
        } else {
            foreach ($changed as $name => $value) {
                if (!is_string($name) || $name === '') {
                    throw new \InvalidArgumentException('changed_fields keys must be non-empty strings');
                }
                $changedMap[$name] = $value;
            }
            $this->assertPayloadOnlyChangedFields($payloadJson, array_keys($changedMap), allowChangedFieldsKey: true);
        }

        $base = $this->readPositiveInt($event, 'base_row_version')
            ?? $this->readPositiveInt($payloadJson, 'base_row_version');
        if ($base === null) {
            throw new \InvalidArgumentException('Native patch requires base_row_version');
        }

        $dictVersion = (string) (
            $event['dictionary_version']
            ?? $payloadJson['dictionary_version']
            ?? $this->metadata->dictionaryVersion()
        );

        $patch = $this->builder->buildFromChangedFields(
            $entityType,
            $entityId,
            $operationId,
            $base,
            $changedMap,
        );
        $patch['dictionary_version'] = $dictVersion;

        return $patch;
    }

    /**
     * @param array<string, mixed> $payloadJson
     * @param list<string> $allowedFields
     */
    private function assertPayloadOnlyChangedFields(
        array $payloadJson,
        array $allowedFields,
        bool $allowChangedFieldsKey = false,
    ): void {
        $metaKeys = [
            'id', 'company_id', 'branch_id', 'row_version', 'client_row_version',
            'base_row_version', 'operation_id', 'dictionary_version', 'contract_version',
            'entity_type', 'entity_id', 'deleted',
        ];
        if ($allowChangedFieldsKey) {
            $metaKeys[] = 'changed_fields';
        }
        $allowed = array_fill_keys(array_merge($metaKeys, $allowedFields), true);

        foreach ($payloadJson as $key => $_) {
            if (!is_string($key)) {
                continue;
            }
            if (!isset($allowed[$key])) {
                throw new \InvalidArgumentException(
                    'Full entity payload is forbidden on patch path; undeclared field: ' . $key
                );
            }
        }
    }

    /**
     * @param array<string, mixed> $event
     * @param array<string, mixed> $payloadJson
     */
    private function resolveOperationId(array $event, array $payloadJson): string
    {
        foreach (['operation_id', 'outbox_id', 'idempotency_key'] as $key) {
            if (isset($event[$key]) && is_string($event[$key]) && $event[$key] !== '') {
                return $event[$key];
            }
            if (isset($payloadJson[$key]) && is_string($payloadJson[$key]) && $payloadJson[$key] !== '') {
                return $payloadJson[$key];
            }
        }

        throw new \InvalidArgumentException('operation_id is required');
    }

    /**
     * @param array<string, mixed> $data
     */
    private function readPositiveInt(array $data, string $key): ?int
    {
        if (!array_key_exists($key, $data)) {
            return null;
        }
        $v = $data[$key];
        if (is_int($v) && $v >= 1) {
            return $v;
        }
        if (is_string($v) && ctype_digit($v) && (int) $v >= 1) {
            return (int) $v;
        }

        return null;
    }
}
