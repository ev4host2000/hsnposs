<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Contract;

/**
 * Loads a versioned Field Dictionary from the filesystem.
 *
 * Pure of repositories / HTTP. Reads JSON contracts only.
 *
 * Layout (Field Dictionary Specification v1.0):
 *   {root}/{version}/manifest.json
 *   {root}/{version}/entities/{entity_type}.json
 */
final class FieldDictionaryLoader
{
    public function __construct(
        private readonly string $dictionaryRoot,
    ) {
        if ($dictionaryRoot === '') {
            throw new \InvalidArgumentException('dictionaryRoot must be non-empty');
        }
    }

    public function load(string $version): FieldDictionary
    {
        $version = trim($version);
        if ($version === '') {
            throw new \InvalidArgumentException('dictionary version must be non-empty');
        }

        $base = rtrim($this->dictionaryRoot, "/\\") . DIRECTORY_SEPARATOR . $version;
        $manifestPath = $base . DIRECTORY_SEPARATOR . 'manifest.json';
        if (!is_file($manifestPath)) {
            throw new \InvalidArgumentException('Field dictionary manifest not found: ' . $manifestPath);
        }

        $manifestRaw = file_get_contents($manifestPath);
        if ($manifestRaw === false) {
            throw new \RuntimeException('Unable to read dictionary manifest: ' . $manifestPath);
        }

        $manifest = json_decode($manifestRaw, true);
        if (!is_array($manifest)) {
            throw new \InvalidArgumentException('Invalid dictionary manifest JSON: ' . $manifestPath);
        }

        $dictVersion = (string) ($manifest['dictionary_version'] ?? '');
        if ($dictVersion === '') {
            throw new \InvalidArgumentException('manifest.dictionary_version is required');
        }
        if ($dictVersion !== $version) {
            throw new \InvalidArgumentException(
                'manifest.dictionary_version "' . $dictVersion . '" does not match requested version "' . $version . '"'
            );
        }

        if (!isset($manifest['entities']) || !is_array($manifest['entities'])) {
            throw new \InvalidArgumentException('manifest.entities must be an array');
        }

        $entities = [];
        foreach ($manifest['entities'] as $entityType) {
            if (!is_string($entityType) || $entityType === '') {
                throw new \InvalidArgumentException('manifest.entities entries must be non-empty strings');
            }
            $entityPath = $base . DIRECTORY_SEPARATOR . 'entities' . DIRECTORY_SEPARATOR . $entityType . '.json';
            if (!is_file($entityPath)) {
                throw new \InvalidArgumentException('Entity dictionary file not found: ' . $entityPath);
            }
            $entityRaw = file_get_contents($entityPath);
            if ($entityRaw === false) {
                throw new \RuntimeException('Unable to read entity dictionary: ' . $entityPath);
            }
            $entityData = json_decode($entityRaw, true);
            if (!is_array($entityData)) {
                throw new \InvalidArgumentException('Invalid entity dictionary JSON: ' . $entityPath);
            }
            $entitySpec = EntitySpec::fromArray($entityData);
            if ($entitySpec->entityType !== $entityType) {
                throw new \InvalidArgumentException(
                    'entity_type mismatch: manifest lists "' . $entityType . '" but file has "' . $entitySpec->entityType . '"'
                );
            }
            $entities[$entityType] = $entitySpec;
        }

        return new FieldDictionary($dictVersion, $entities);
    }

    /**
     * Load dictionary from an in-memory structure (unit tests / fixtures).
     *
     * @param array{dictionary_version: string, entities: array<string, array<string, mixed>>} $payload
     */
    public static function fromArray(array $payload): FieldDictionary
    {
        $version = (string) ($payload['dictionary_version'] ?? '');
        if ($version === '') {
            throw new \InvalidArgumentException('dictionary_version is required');
        }
        if (!isset($payload['entities']) || !is_array($payload['entities'])) {
            throw new \InvalidArgumentException('entities map is required');
        }

        $entities = [];
        foreach ($payload['entities'] as $entityType => $entityData) {
            if (!is_string($entityType) || $entityType === '') {
                throw new \InvalidArgumentException('entity keys must be non-empty strings');
            }
            if (!is_array($entityData)) {
                throw new \InvalidArgumentException('entity value must be array for: ' . $entityType);
            }
            if (!isset($entityData['entity_type'])) {
                $entityData['entity_type'] = $entityType;
            }
            $spec = EntitySpec::fromArray($entityData);
            if ($spec->entityType !== $entityType) {
                throw new \InvalidArgumentException('entity_type key mismatch for: ' . $entityType);
            }
            $entities[$entityType] = $spec;
        }

        return new FieldDictionary($version, $entities);
    }
}
