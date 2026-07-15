<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Support;

use MizaCloud\Modules\Sync\Contract\ChangeDetectionEngine;
use MizaCloud\Modules\Sync\Contract\FieldMetadataProvider;
use MizaCloud\Modules\Sync\Contract\PatchBuilder;

/**
 * Update Contract v2 §18 — Full Entity → Patch transitional adapter (shared).
 *
 * Entity-agnostic: Products / Partners / later catalog entities use the same adapter.
 */
final class CatalogFullToPatchAdapter
{
    public function __construct(
        private readonly ChangeDetectionEngine $detector,
        private readonly PatchBuilder $builder,
        private readonly FieldMetadataProvider $metadata,
    ) {
    }

    /**
     * @param array<string, mixed> $serverRow DB / authoritative row (dictionary field names)
     * @param array<string, mixed> $fullPayload legacy full (or near-full) entity payload
     * @return array{
     *   entity_type: string,
     *   entity_id: string,
     *   operation: string,
     *   operation_id: string,
     *   base_row_version: int,
     *   dictionary_version: string,
     *   changed_fields: array<string, mixed>,
     *   is_no_op: bool,
     *   adapted_from: string
     * }
     */
    public function adapt(
        string $entityType,
        string $entityId,
        array $serverRow,
        array $fullPayload,
        string $operationId,
        ?int $baseRowVersion = null,
    ): array {
        $serverVersion = max(1, (int) ($serverRow['row_version'] ?? 1));
        $base = $baseRowVersion ?? $serverVersion;
        if ($base < 1) {
            throw new \InvalidArgumentException('base_row_version must be >= 1');
        }

        $baseSnapshot = $this->snapshotFromServerRow($entityType, $serverRow);
        $nextSnapshot = $this->snapshotFromFullPayload($entityType, $fullPayload, $baseSnapshot);

        $patch = $this->builder->buildUpdatePatch(
            $entityType,
            $entityId,
            $operationId,
            $base,
            $baseSnapshot,
            $nextSnapshot,
        );

        $patch['adapted_from'] = 'full_entity';

        return $patch;
    }

    /**
     * @param array<string, mixed> $serverRow
     * @return array<string, mixed>
     */
    public function snapshotFromServerRow(string $entityType, array $serverRow): array
    {
        $out = [];
        foreach ($this->metadata->patchableFieldNames($entityType) as $name) {
            if (array_key_exists($name, $serverRow)) {
                $out[$name] = $serverRow[$name];
            }
        }

        return $out;
    }

    /**
     * Fields absent from payload keep the base (authoritative) value —
     * absence must not clear nullable fields (Update Contract §14).
     *
     * @param array<string, mixed> $fullPayload
     * @param array<string, mixed> $baseSnapshot
     * @return array<string, mixed>
     */
    public function snapshotFromFullPayload(
        string $entityType,
        array $fullPayload,
        array $baseSnapshot,
    ): array {
        $next = $baseSnapshot;
        foreach ($this->metadata->patchableFieldNames($entityType) as $name) {
            if (!array_key_exists($name, $fullPayload)) {
                continue;
            }
            $next[$name] = $fullPayload[$name];
        }

        return $next;
    }

    /**
     * @param array<string, mixed> $event
     * @param array<string, mixed> $payloadJson
     */
    public static function isNativePatchEvent(string $operation, array $event, array $payloadJson): bool
    {
        $operation = strtolower(trim($operation));
        if ($operation === 'patch') {
            return true;
        }

        if (isset($event['changed_fields']) && is_array($event['changed_fields'])) {
            return true;
        }

        if (isset($payloadJson['changed_fields']) && is_array($payloadJson['changed_fields'])) {
            return true;
        }

        $contract = $event['contract_version'] ?? $payloadJson['contract_version'] ?? null;
        if ($contract === 2 || $contract === '2' || $contract === 'v2') {
            return true;
        }

        return false;
    }
}
