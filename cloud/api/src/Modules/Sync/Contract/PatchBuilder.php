<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Contract;

/**
 * Builds an Update Contract v2 patch document from base/next snapshots.
 *
 * Pure business logic — no repository / HTTP.
 */
final class PatchBuilder
{
    public const OPERATION_UPDATE = 'update';

    public function __construct(
        private readonly ChangeDetectionEngine $detector,
        private readonly FieldMetadataProvider $metadata,
    ) {
    }

    /**
     * @param array<string, mixed> $baseSnapshot
     * @param array<string, mixed> $nextSnapshot
     * @return array{
     *   entity_type: string,
     *   entity_id: string,
     *   operation: string,
     *   operation_id: string,
     *   base_row_version: int,
     *   dictionary_version: string,
     *   changed_fields: array<string, mixed>,
     *   is_no_op: bool
     * }
     */
    public function buildUpdatePatch(
        string $entityType,
        string $entityId,
        string $operationId,
        int $baseRowVersion,
        array $baseSnapshot,
        array $nextSnapshot,
    ): array {
        if ($entityType === '') {
            throw new \InvalidArgumentException('entity_type is required');
        }
        if ($entityId === '') {
            throw new \InvalidArgumentException('entity_id is required');
        }
        if ($operationId === '') {
            throw new \InvalidArgumentException('operation_id is required');
        }
        if ($baseRowVersion < 1) {
            throw new \InvalidArgumentException('base_row_version must be >= 1');
        }
        if (!$this->metadata->hasEntity($entityType)) {
            throw new \InvalidArgumentException('Unknown entity_type: ' . $entityType);
        }

        $changed = $this->detector->detect($entityType, $baseSnapshot, $nextSnapshot);

        return [
            'entity_type' => $entityType,
            'entity_id' => $entityId,
            'operation' => self::OPERATION_UPDATE,
            'operation_id' => $operationId,
            'base_row_version' => $baseRowVersion,
            'dictionary_version' => $this->metadata->dictionaryVersion(),
            'changed_fields' => $changed,
            'is_no_op' => $changed === [],
        ];
    }

    /**
     * Build a patch from an explicit changed_fields map (already computed).
     *
     * @param array<string, mixed> $changedFields
     * @return array{
     *   entity_type: string,
     *   entity_id: string,
     *   operation: string,
     *   operation_id: string,
     *   base_row_version: int,
     *   dictionary_version: string,
     *   changed_fields: array<string, mixed>,
     *   is_no_op: bool
     * }
     */
    public function buildFromChangedFields(
        string $entityType,
        string $entityId,
        string $operationId,
        int $baseRowVersion,
        array $changedFields,
    ): array {
        if ($entityType === '') {
            throw new \InvalidArgumentException('entity_type is required');
        }
        if ($entityId === '') {
            throw new \InvalidArgumentException('entity_id is required');
        }
        if ($operationId === '') {
            throw new \InvalidArgumentException('operation_id is required');
        }
        if ($baseRowVersion < 1) {
            throw new \InvalidArgumentException('base_row_version must be >= 1');
        }
        if (!$this->metadata->hasEntity($entityType)) {
            throw new \InvalidArgumentException('Unknown entity_type: ' . $entityType);
        }

        $normalized = [];
        foreach ($changedFields as $name => $value) {
            if (!is_string($name) || $name === '') {
                throw new \InvalidArgumentException('changed_fields keys must be non-empty strings');
            }
            if (!$this->metadata->isPatchable($entityType, $name)) {
                throw new \InvalidArgumentException('Field is not patchable: ' . $name);
            }
            $field = $this->metadata->field($entityType, $name);
            $normalized[$name] = $this->detector->normalize($field, $value);
        }

        return [
            'entity_type' => $entityType,
            'entity_id' => $entityId,
            'operation' => self::OPERATION_UPDATE,
            'operation_id' => $operationId,
            'base_row_version' => $baseRowVersion,
            'dictionary_version' => $this->metadata->dictionaryVersion(),
            'changed_fields' => $normalized,
            'is_no_op' => $normalized === [],
        ];
    }
}
