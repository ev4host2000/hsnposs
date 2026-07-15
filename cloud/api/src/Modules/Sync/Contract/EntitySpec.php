<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Contract;

/**
 * Immutable entity metadata from the Field Dictionary Specification v1.0.
 */
final class EntitySpec
{
    /**
     * @param array<string, FieldSpec> $fields keyed by field name
     */
    public function __construct(
        public readonly string $entityType,
        public readonly array $fields,
    ) {
        if ($entityType === '') {
            throw new \InvalidArgumentException('entity_type must be non-empty');
        }
    }

    /**
     * @param array<string, mixed> $raw
     */
    public static function fromArray(array $raw): self
    {
        if (!isset($raw['entity_type']) || !is_string($raw['entity_type']) || $raw['entity_type'] === '') {
            throw new \InvalidArgumentException('EntitySpec requires entity_type');
        }
        if (!isset($raw['fields']) || !is_array($raw['fields'])) {
            throw new \InvalidArgumentException('EntitySpec requires fields array for: ' . $raw['entity_type']);
        }

        $fields = [];
        foreach ($raw['fields'] as $fieldRaw) {
            if (!is_array($fieldRaw)) {
                throw new \InvalidArgumentException('Each field must be an object for entity: ' . $raw['entity_type']);
            }
            $spec = FieldSpec::fromArray($fieldRaw);
            if (isset($fields[$spec->name])) {
                throw new \InvalidArgumentException('Duplicate field name in entity ' . $raw['entity_type'] . ': ' . $spec->name);
            }
            $fields[$spec->name] = $spec;
        }

        return new self($raw['entity_type'], $fields);
    }

    public function hasField(string $name): bool
    {
        return isset($this->fields[$name]);
    }

    public function field(string $name): FieldSpec
    {
        if (!isset($this->fields[$name])) {
            throw new \InvalidArgumentException('Unknown field "' . $name . '" on entity "' . $this->entityType . '"');
        }

        return $this->fields[$name];
    }

    /**
     * @return list<FieldSpec>
     */
    public function patchableFields(): array
    {
        $out = [];
        foreach ($this->fields as $field) {
            if ($field->patchable && !$field->deprecated) {
                $out[] = $field;
            }
        }

        return $out;
    }
}
