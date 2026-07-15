<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Contract;

/**
 * Validates an Update Contract v2 patch against the Field Dictionary.
 *
 * Pure business logic — no repository / HTTP.
 */
final class PatchValidator
{
    public const RESULT_VALID = 'valid';
    public const RESULT_INVALID = 'invalid';

    public const PATH_PRODUCT_CATALOG_PATCH = 'product_catalog_patch';
    public const PATH_CUSTOMER_CATALOG_PATCH = 'customer_catalog_patch';
    public const PATH_SUPPLIER_CATALOG_PATCH = 'supplier_catalog_patch';
    public const PATH_PRODUCT_CATEGORY_CATALOG_PATCH = 'product_category_catalog_patch';
    public const PATH_PRODUCT_UNIT_CATALOG_PATCH = 'product_unit_catalog_patch';
    public const PATH_TAX_CATALOG_PATCH = 'tax_catalog_patch';
    public const PATH_PRICE_LIST_CATALOG_PATCH = 'price_list_catalog_patch';

    public function __construct(
        private readonly FieldMetadataProvider $metadata,
        private readonly ChangeDetectionEngine $detector,
    ) {
    }

    /**
     * @param array<string, mixed> $patch
     * @return array{
     *   status: self::RESULT_*,
     *   errors: list<string>,
     *   normalized_changed_fields: array<string, mixed>|null
     * }
     */
    public function validate(array $patch, ?string $entityPath = null): array
    {
        $errors = [];

        $entityType = $patch['entity_type'] ?? null;
        if (!is_string($entityType) || $entityType === '') {
            $errors[] = 'entity_type is required';
        }

        $entityId = $patch['entity_id'] ?? null;
        if (!is_string($entityId) || $entityId === '') {
            $errors[] = 'entity_id is required';
        }

        $operation = $patch['operation'] ?? null;
        if (!is_string($operation) || strtolower(trim($operation)) !== PatchBuilder::OPERATION_UPDATE) {
            $errors[] = 'operation must be "update"';
        }

        $operationId = $patch['operation_id'] ?? null;
        if (!is_string($operationId) || $operationId === '') {
            $errors[] = 'operation_id is required';
        }

        $baseRowVersion = $patch['base_row_version'] ?? null;
        if (!is_int($baseRowVersion) && !(is_string($baseRowVersion) && ctype_digit($baseRowVersion))) {
            $errors[] = 'base_row_version must be a positive integer';
        } elseif ((int) $baseRowVersion < 1) {
            $errors[] = 'base_row_version must be >= 1';
        }

        $dictionaryVersion = $patch['dictionary_version'] ?? null;
        if (!is_string($dictionaryVersion) || $dictionaryVersion === '') {
            $errors[] = 'dictionary_version is required';
        } elseif ($dictionaryVersion !== $this->metadata->dictionaryVersion()) {
            $errors[] = 'dictionary_version mismatch: expected '
                . $this->metadata->dictionaryVersion()
                . ', got '
                . $dictionaryVersion;
        }

        $changedFields = $patch['changed_fields'] ?? null;
        if (!is_array($changedFields)) {
            $errors[] = 'changed_fields must be an object/map';
            $changedFields = null;
        }

        if ($entityType !== null && is_string($entityType) && $entityType !== '' && !$this->metadata->hasEntity($entityType)) {
            $errors[] = 'Unknown entity_type: ' . $entityType;
            $entityType = null;
        }

        $normalized = null;
        if ($entityType !== null && $changedFields !== null) {
            $normalized = [];
            $path = $entityPath ?? match ($entityType) {
                'product' => self::PATH_PRODUCT_CATALOG_PATCH,
                'customer' => self::PATH_CUSTOMER_CATALOG_PATCH,
                'supplier' => self::PATH_SUPPLIER_CATALOG_PATCH,
                'product_category' => self::PATH_PRODUCT_CATEGORY_CATALOG_PATCH,
                'product_unit' => self::PATH_PRODUCT_UNIT_CATALOG_PATCH,
                'tax' => self::PATH_TAX_CATALOG_PATCH,
                'price_list' => self::PATH_PRICE_LIST_CATALOG_PATCH,
                default => null,
            };

            foreach ($changedFields as $name => $value) {
                if (!is_string($name) || $name === '') {
                    $errors[] = 'changed_fields keys must be non-empty strings';
                    continue;
                }

                if (!$this->metadata->hasField($entityType, $name)) {
                    $errors[] = 'Unknown field in changed_fields: ' . $name;
                    continue;
                }

                $field = $this->metadata->field($entityType, $name);

                if ($field->deprecated) {
                    $errors[] = 'Deprecated field cannot be patched: ' . $name;
                    continue;
                }

                if (!$field->patchable) {
                    $errors[] = 'Field is not patchable: ' . $name;
                    continue;
                }

                if ($path !== null && in_array($path, $field->forbiddenOnEntityPaths, true)) {
                    $errors[] = 'Field is forbidden on path "' . $path . '": ' . $name;
                    continue;
                }

                if ($value === null && !$field->nullable) {
                    $errors[] = 'Field does not allow null: ' . $name;
                    continue;
                }

                try {
                    $normalized[$name] = $this->detector->normalize($field, $value);
                } catch (\InvalidArgumentException $e) {
                    $errors[] = 'Invalid value for field ' . $name . ': ' . $e->getMessage();
                }
            }
        }

        if ($errors !== []) {
            return [
                'status' => self::RESULT_INVALID,
                'errors' => $errors,
                'normalized_changed_fields' => null,
            ];
        }

        return [
            'status' => self::RESULT_VALID,
            'errors' => [],
            'normalized_changed_fields' => $normalized ?? [],
        ];
    }

    public function isValid(array $patch, ?string $entityPath = null): bool
    {
        return $this->validate($patch, $entityPath)['status'] === self::RESULT_VALID;
    }
}
