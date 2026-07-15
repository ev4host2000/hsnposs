<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Contract;

/**
 * Read-only accessor over a loaded Field Dictionary.
 *
 * Field Dictionary Specification v1.0 — Field Metadata Provider.
 */
final class FieldMetadataProvider
{
    public function __construct(
        private readonly FieldDictionary $dictionary,
    ) {
    }

    public function dictionaryVersion(): string
    {
        return $this->dictionary->dictionaryVersion;
    }

    /**
     * @return list<string>
     */
    public function entityTypes(): array
    {
        return $this->dictionary->entityTypes();
    }

    public function hasEntity(string $entityType): bool
    {
        return $this->dictionary->hasEntity($entityType);
    }

    public function entity(string $entityType): EntitySpec
    {
        return $this->dictionary->entity($entityType);
    }

    public function hasField(string $entityType, string $fieldName): bool
    {
        if (!$this->dictionary->hasEntity($entityType)) {
            return false;
        }

        return $this->dictionary->entity($entityType)->hasField($fieldName);
    }

    public function field(string $entityType, string $fieldName): FieldSpec
    {
        return $this->dictionary->entity($entityType)->field($fieldName);
    }

    public function isPatchable(string $entityType, string $fieldName): bool
    {
        $field = $this->field($entityType, $fieldName);

        return $field->patchable && !$field->deprecated;
    }

    public function isSyncable(string $entityType, string $fieldName): bool
    {
        $field = $this->field($entityType, $fieldName);

        return $field->syncable && !$field->deprecated;
    }

    /**
     * @return list<string>
     */
    public function patchableFieldNames(string $entityType): array
    {
        $names = [];
        foreach ($this->entity($entityType)->patchableFields() as $field) {
            $names[] = $field->name;
        }

        return $names;
    }

    public function isForbiddenOnPath(string $entityType, string $fieldName, string $entityPath): bool
    {
        $field = $this->field($entityType, $fieldName);

        return in_array($entityPath, $field->forbiddenOnEntityPaths, true);
    }
}
