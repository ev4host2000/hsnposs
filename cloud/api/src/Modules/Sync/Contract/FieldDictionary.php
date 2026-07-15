<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Contract;

/**
 * Loaded Field Dictionary snapshot (versioned).
 */
final class FieldDictionary
{
    /**
     * @param array<string, EntitySpec> $entities keyed by entity_type
     */
    public function __construct(
        public readonly string $dictionaryVersion,
        public readonly array $entities,
    ) {
        if ($dictionaryVersion === '') {
            throw new \InvalidArgumentException('dictionary_version must be non-empty');
        }
    }

    public function hasEntity(string $entityType): bool
    {
        return isset($this->entities[$entityType]);
    }

    public function entity(string $entityType): EntitySpec
    {
        if (!isset($this->entities[$entityType])) {
            throw new \InvalidArgumentException('Unknown entity_type: ' . $entityType);
        }

        return $this->entities[$entityType];
    }

    /**
     * @return list<string>
     */
    public function entityTypes(): array
    {
        return array_keys($this->entities);
    }
}
