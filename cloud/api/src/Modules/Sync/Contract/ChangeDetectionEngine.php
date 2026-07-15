<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Contract;

/**
 * Field Change Detection Engine — Field Change Detection Specification v1.0.
 *
 * Pure comparison: base snapshot vs next snapshot → changed_fields map.
 * Clients and cloud must produce identical results for the same inputs + dictionary.
 */
final class ChangeDetectionEngine
{
    public function __construct(
        private readonly FieldMetadataProvider $metadata,
    ) {
    }

    /**
     * Detect changed patchable fields between base and next entity snapshots.
     *
     * @param array<string, mixed> $baseSnapshot field => value (previous accepted state)
     * @param array<string, mixed> $nextSnapshot field => value (intended new state)
     * @return array<string, mixed> changed_fields map (field => next normalized value)
     */
    public function detect(string $entityType, array $baseSnapshot, array $nextSnapshot): array
    {
        $entity = $this->metadata->entity($entityType);
        $changed = [];

        foreach ($entity->patchableFields() as $field) {
            $baseRaw = array_key_exists($field->name, $baseSnapshot)
                ? $baseSnapshot[$field->name]
                : $field->defaultValue;
            $nextRaw = array_key_exists($field->name, $nextSnapshot)
                ? $nextSnapshot[$field->name]
                : $field->defaultValue;

            $baseNorm = $this->normalize($field, $baseRaw);
            $nextNorm = $this->normalize($field, $nextRaw);

            if (!$this->valuesEqual($field, $baseNorm, $nextNorm)) {
                $changed[$field->name] = $nextNorm;
            }
        }

        return $changed;
    }

    /**
     * Normalize a single field value for comparison / patch emission.
     */
    public function normalize(FieldSpec $field, mixed $value): mixed
    {
        if ($value === null) {
            if (!$field->nullable && $field->defaultValue !== null) {
                return $this->normalize($field, $field->defaultValue);
            }

            return null;
        }

        if ($field->emptyAsNull && is_string($value) && trim($value) === '') {
            return null;
        }

        return match ($field->comparisonRule) {
            'string_default' => $this->normalizeString($value),
            'decimal_scale' => $this->normalizeDecimal($value, $field->decimalScale ?? 4),
            'boolean_default' => $this->normalizeBoolean($value),
            'integer_default' => $this->normalizeInteger($value),
            'uuid_canonical' => $this->normalizeUuid($value),
            'datetime_iso8601' => $this->normalizeDateTime($value),
            'image_url_special' => $this->normalizeImageUrl($value, $field->emptyAsNull),
            default => throw new \InvalidArgumentException(
                'Unsupported comparison_rule "' . $field->comparisonRule . '" for field ' . $field->name
            ),
        };
    }

    public function valuesEqual(FieldSpec $field, mixed $a, mixed $b): bool
    {
        if ($a === null && $b === null) {
            return true;
        }
        if ($a === null || $b === null) {
            return false;
        }

        return match ($field->comparisonRule) {
            'decimal_scale' => (string) $a === (string) $b,
            'boolean_default' => (bool) $a === (bool) $b,
            'integer_default' => (int) $a === (int) $b,
            default => $a === $b,
        };
    }

    private function normalizeString(mixed $value): string
    {
        if (is_bool($value) || is_array($value) || is_object($value)) {
            throw new \InvalidArgumentException('string field cannot accept complex/bool value');
        }

        return (string) $value;
    }

    private function normalizeDecimal(mixed $value, int $scale): string
    {
        if (is_bool($value) || is_array($value) || is_object($value) || $value === null) {
            throw new \InvalidArgumentException('decimal field requires numeric value');
        }
        if (is_string($value) && trim($value) === '') {
            throw new \InvalidArgumentException('decimal field cannot be empty string');
        }

        if (!is_numeric($value)) {
            throw new \InvalidArgumentException('decimal field requires numeric value');
        }

        return number_format((float) $value, $scale, '.', '');
    }

    private function normalizeBoolean(mixed $value): bool
    {
        if (is_bool($value)) {
            return $value;
        }
        if (is_int($value) || is_float($value)) {
            if ($value === 1 || $value === 1.0) {
                return true;
            }
            if ($value === 0 || $value === 0.0) {
                return false;
            }
            throw new \InvalidArgumentException('boolean field numeric must be 0 or 1');
        }
        if (is_string($value)) {
            $v = strtolower(trim($value));
            if (in_array($v, ['1', 'true', 'yes'], true)) {
                return true;
            }
            if (in_array($v, ['0', 'false', 'no', ''], true)) {
                return false;
            }
        }

        throw new \InvalidArgumentException('boolean field has invalid value');
    }

    private function normalizeInteger(mixed $value): int
    {
        if (is_bool($value) || is_array($value) || is_object($value)) {
            throw new \InvalidArgumentException('integer field has invalid value');
        }
        if (is_int($value)) {
            return $value;
        }
        if (is_float($value)) {
            if (floor($value) !== $value) {
                throw new \InvalidArgumentException('integer field cannot be fractional');
            }

            return (int) $value;
        }
        if (is_string($value)) {
            $v = trim($value);
            if ($v === '' || !preg_match('/^-?\d+$/', $v)) {
                throw new \InvalidArgumentException('integer field has invalid value');
            }

            return (int) $v;
        }

        throw new \InvalidArgumentException('integer field has invalid value');
    }

    private function normalizeUuid(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }
        if (!is_string($value)) {
            throw new \InvalidArgumentException('uuid field must be string or null');
        }
        $v = strtolower(trim($value));
        if ($v === '') {
            return null;
        }
        if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/', $v)) {
            throw new \InvalidArgumentException('uuid field has invalid format');
        }

        return $v;
    }

    private function normalizeDateTime(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }
        if (!is_string($value) || trim($value) === '') {
            throw new \InvalidArgumentException('datetime field must be non-empty ISO-8601 string or null');
        }
        $ts = strtotime($value);
        if ($ts === false) {
            throw new \InvalidArgumentException('datetime field has invalid value');
        }

        return gmdate('Y-m-d\TH:i:s\Z', $ts);
    }

    private function normalizeImageUrl(mixed $value, bool $emptyAsNull): ?string
    {
        if ($value === null) {
            return null;
        }
        if (!is_string($value)) {
            throw new \InvalidArgumentException('image_url field must be string or null');
        }
        $v = trim($value);
        if ($v === '') {
            return $emptyAsNull ? null : '';
        }

        return $v;
    }
}
