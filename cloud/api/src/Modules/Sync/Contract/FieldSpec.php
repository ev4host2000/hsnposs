<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Contract;

/**
 * Immutable field metadata entry from the Field Dictionary Specification v1.0.
 */
final class FieldSpec
{
    public function __construct(
        public readonly string $name,
        public readonly string $type,
        public readonly bool $nullable,
        public readonly mixed $defaultValue,
        public readonly string $comparisonRule,
        public readonly string $securityLevel,
        public readonly bool $patchable,
        public readonly bool $syncable,
        public readonly bool $searchable,
        public readonly bool $sortable,
        public readonly bool $localized,
        public readonly bool $deprecated,
        public readonly ?int $decimalScale = null,
        public readonly bool $emptyAsNull = false,
        /** @var list<string> */
        public readonly array $forbiddenOnEntityPaths = [],
    ) {
    }

    /**
     * @param array<string, mixed> $raw
     */
    public static function fromArray(array $raw): self
    {
        if (!isset($raw['name']) || !is_string($raw['name']) || $raw['name'] === '') {
            throw new \InvalidArgumentException('FieldSpec requires non-empty name');
        }
        if (!isset($raw['type']) || !is_string($raw['type']) || $raw['type'] === '') {
            throw new \InvalidArgumentException('FieldSpec requires type for field: ' . (string) ($raw['name'] ?? ''));
        }
        if (!isset($raw['comparison_rule']) || !is_string($raw['comparison_rule'])) {
            throw new \InvalidArgumentException('FieldSpec requires comparison_rule for field: ' . $raw['name']);
        }

        $forbidden = [];
        if (isset($raw['forbidden_on_entity_paths']) && is_array($raw['forbidden_on_entity_paths'])) {
            foreach ($raw['forbidden_on_entity_paths'] as $path) {
                if (!is_string($path) || $path === '') {
                    throw new \InvalidArgumentException('forbidden_on_entity_paths must be list of non-empty strings');
                }
                $forbidden[] = $path;
            }
        }

        $decimalScale = null;
        if (array_key_exists('decimal_scale', $raw) && $raw['decimal_scale'] !== null) {
            if (!is_int($raw['decimal_scale']) && !(is_string($raw['decimal_scale']) && ctype_digit($raw['decimal_scale']))) {
                throw new \InvalidArgumentException('decimal_scale must be int for field: ' . $raw['name']);
            }
            $decimalScale = (int) $raw['decimal_scale'];
            if ($decimalScale < 0) {
                throw new \InvalidArgumentException('decimal_scale must be >= 0 for field: ' . $raw['name']);
            }
        }

        return new self(
            name: $raw['name'],
            type: $raw['type'],
            nullable: (bool) ($raw['nullable'] ?? false),
            defaultValue: $raw['default_value'] ?? null,
            comparisonRule: $raw['comparison_rule'],
            securityLevel: (string) ($raw['security_level'] ?? 'staff'),
            patchable: (bool) ($raw['patchable'] ?? false),
            syncable: (bool) ($raw['syncable'] ?? false),
            searchable: (bool) ($raw['searchable'] ?? false),
            sortable: (bool) ($raw['sortable'] ?? false),
            localized: (bool) ($raw['localized'] ?? false),
            deprecated: (bool) ($raw['deprecated'] ?? false),
            decimalScale: $decimalScale,
            emptyAsNull: (bool) ($raw['empty_as_null'] ?? false),
            forbiddenOnEntityPaths: $forbidden,
        );
    }

    /**
     * @return array<string, mixed>
     */
    public function toArray(): array
    {
        return [
            'name' => $this->name,
            'type' => $this->type,
            'nullable' => $this->nullable,
            'default_value' => $this->defaultValue,
            'comparison_rule' => $this->comparisonRule,
            'security_level' => $this->securityLevel,
            'patchable' => $this->patchable,
            'syncable' => $this->syncable,
            'searchable' => $this->searchable,
            'sortable' => $this->sortable,
            'localized' => $this->localized,
            'deprecated' => $this->deprecated,
            'decimal_scale' => $this->decimalScale,
            'empty_as_null' => $this->emptyAsNull,
            'forbidden_on_entity_paths' => $this->forbiddenOnEntityPaths,
        ];
    }
}
