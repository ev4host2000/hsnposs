<?php

declare(strict_types=1);

/**
 * Unit tests for ProductsSyncRepository version-gate wiring (no DB).
 *
 * Covers CatalogVersionGate decisions + payload equality semantics used by
 * ProductsSyncRepository (stock_qty excluded; image compared only when present).
 *
 * Run: php cloud/api/src/Modules/Sync/test_products_sync_repository_version_unit.php
 */

spl_autoload_register(static function (string $class): void {
    $prefix = 'MizaCloud\\';
    if (!str_starts_with($class, $prefix)) {
        return;
    }
    $rel = str_replace('\\', '/', substr($class, strlen($prefix)));
    $path = dirname(__DIR__, 3) . '/src/' . $rel . '.php';
    if (is_file($path)) {
        require_once $path;
    }
});

use MizaCloud\Modules\Sync\Support\CatalogVersionGate;

$failed = 0;
$passed = 0;

function assertSame(mixed $expected, mixed $actual, string $msg): void
{
    global $failed, $passed;
    if ($expected !== $actual) {
        ++$failed;
        fwrite(STDERR, "FAIL: {$msg}\n  expected: " . var_export($expected, true)
            . "\n  actual:   " . var_export($actual, true) . "\n");
        return;
    }
    ++$passed;
    echo "OK: {$msg}\n";
}

/**
 * Mirrors ProductsSyncRepository::productPayloadMatchesServerRow (stock excluded).
 *
 * @param array<string, mixed> $payload
 * @param array<string, mixed> $row
 */
function productPayloadMatchesServerRow(array $payload, array $row, bool $hasImageUrl): bool
{
    if (($row['deleted_at'] ?? null) !== null) {
        return false;
    }

    $floatEquals = static fn (float $a, float $b): bool => abs($a - $b) < 1e-9;
    $nullableStringEquals = static function (?string $a, ?string $b): bool {
        $norm = static function (?string $v): ?string {
            if ($v === null) {
                return null;
            }
            $t = trim($v);

            return $t === '' ? null : $t;
        };

        return $norm($a) === $norm($b);
    };

    if (trim((string) ($payload['name'] ?? '')) !== trim((string) ($row['name'] ?? ''))) {
        return false;
    }
    if (!$floatEquals((float) ($payload['sale_price'] ?? 0), (float) ($row['sale_price'] ?? 0))) {
        return false;
    }
    if (!$floatEquals((float) ($payload['cost_price'] ?? 0), (float) ($row['cost_price'] ?? 0))) {
        return false;
    }
    if (!$nullableStringEquals(
        isset($payload['barcode']) ? (string) $payload['barcode'] : null,
        $row['barcode'] !== null ? (string) $row['barcode'] : null,
    )) {
        return false;
    }

    $payloadCategory = isset($payload['category_id']) && $payload['category_id'] !== ''
        ? (string) $payload['category_id']
        : null;
    $rowCategory = $row['category_id'] !== null && $row['category_id'] !== ''
        ? (string) $row['category_id']
        : null;
    if ($payloadCategory !== $rowCategory) {
        return false;
    }

    if (!$nullableStringEquals(
        isset($payload['unit_name']) ? (string) $payload['unit_name'] : null,
        $row['unit_name'] !== null ? (string) $row['unit_name'] : null,
    )) {
        return false;
    }
    if (!$nullableStringEquals(
        isset($payload['description']) ? (string) $payload['description'] : null,
        $row['description'] !== null ? (string) $row['description'] : null,
    )) {
        return false;
    }
    if ((bool) ($payload['is_hidden'] ?? false) !== (bool) ($row['is_hidden'] ?? false)) {
        return false;
    }
    if ((bool) ($payload['is_frozen'] ?? false) !== (bool) ($row['is_frozen'] ?? false)) {
        return false;
    }
    if ((bool) ($payload['is_service'] ?? false) !== (bool) ($row['is_service'] ?? false)) {
        return false;
    }
    if ((int) ($payload['sort_order'] ?? 0) !== (int) ($row['sort_order'] ?? 0)) {
        return false;
    }

    if ($hasImageUrl) {
        $raw = $payload['image_url'];
        $payloadImage = ($raw === null || $raw === '') ? null : (string) $raw;
        $rowImage = $row['image_url'] !== null && $row['image_url'] !== ''
            ? (string) $row['image_url']
            : null;
        if ($payloadImage !== $rowImage) {
            return false;
        }
    }

    return true;
}

function decideProduct(
    string $operation,
    ?int $serverVersion,
    int $clientVersion,
    array $payload,
    ?array $serverRow,
    bool $hasImageUrl = false,
): string {
    $matches = false;
    if ($operation === 'delete') {
        $matches = $serverRow !== null && ($serverRow['deleted_at'] ?? null) !== null;
    } elseif ($serverRow !== null) {
        $matches = productPayloadMatchesServerRow($payload, $serverRow, $hasImageUrl);
    }

    return CatalogVersionGate::decide($operation, $serverVersion, $clientVersion, $matches);
}

echo "=== ProductsSyncRepository version-gate unit tests ===\n\n";

$server = [
    'name' => 'Milk',
    'sale_price' => 6.5,
    'cost_price' => 5.0,
    'stock_qty' => 48.0,
    'barcode' => '123',
    'category_id' => null,
    'unit_name' => 'pcs',
    'description' => null,
    'image_url' => 'https://cdn/a.png',
    'is_hidden' => false,
    'is_frozen' => false,
    'is_service' => false,
    'sort_order' => 0,
    'row_version' => 5,
    'deleted_at' => null,
];

$samePayload = [
    'name' => 'Milk',
    'sale_price' => 6.5,
    'cost_price' => 5.0,
    'stock_qty' => 999.0, // must NOT affect equality
    'barcode' => '123',
    'unit_name' => 'pcs',
    'is_hidden' => false,
    'is_frozen' => false,
    'is_service' => false,
    'sort_order' => 0,
];

$diffPayload = $samePayload;
$diffPayload['sale_price'] = 9.0;

echo "-- Lost Update / Silent Overwrite prevention --\n";
assertSame(
    CatalogVersionGate::DECISION_CONFLICT,
    decideProduct('update', 5, 2, $diffPayload, $server),
    'stale client (2 < 5) with different price => version_conflict (no silent overwrite)',
);
assertSame(
    CatalogVersionGate::DECISION_CONFLICT,
    decideProduct('update', 5, 5, $diffPayload, $server),
    'equal version with different price => version_conflict (no lost update)',
);

echo "\n-- Safe Equality no-op --\n";
assertSame(
    CatalogVersionGate::DECISION_NO_OP,
    decideProduct('update', 5, 5, $samePayload, $server),
    'equal version + matching catalog fields => no_op',
);
assertSame(
    true,
    productPayloadMatchesServerRow($samePayload, $server, false),
    'stock_qty difference does not break catalog equality',
);

echo "\n-- Apply newer --\n";
assertSame(
    CatalogVersionGate::DECISION_APPLY,
    decideProduct('update', 5, 6, $diffPayload, $server),
    'newer client (6 > 5) => apply',
);

echo "\n-- Create جديد --\n";
assertSame(
    CatalogVersionGate::DECISION_APPLY,
    decideProduct('create', null, 1, $samePayload, null),
    'create with no server row => apply',
);

echo "\n-- Delete قديم / جديد --\n";
assertSame(
    CatalogVersionGate::DECISION_CONFLICT,
    decideProduct('delete', 5, 2, [], $server),
    'delete stale => version_conflict',
);
assertSame(
    CatalogVersionGate::DECISION_APPLY,
    decideProduct('delete', 5, 7, [], $server),
    'delete newer => apply',
);
assertSame(
    CatalogVersionGate::DECISION_APPLY,
    decideProduct('delete', 5, 5, [], $server),
    'delete == on active row => apply',
);
$deletedServer = $server;
$deletedServer['deleted_at'] = '2026-01-01 00:00:00';
assertSame(
    CatalogVersionGate::DECISION_NO_OP,
    decideProduct('delete', 5, 5, [], $deletedServer),
    'delete == when already deleted => no_op',
);

echo "\n-- Image equality only when image_url present --\n";
assertSame(
    true,
    productPayloadMatchesServerRow($samePayload, $server, false),
    'omitting image_url does not compare image',
);
$sameWithImage = $samePayload + ['image_url' => 'https://cdn/a.png'];
assertSame(
    true,
    productPayloadMatchesServerRow($sameWithImage, $server, true),
    'matching image_url equals',
);
$diffImage = $samePayload + ['image_url' => 'https://cdn/b.png'];
assertSame(
    false,
    productPayloadMatchesServerRow($diffImage, $server, true),
    'different image_url does not equal',
);

echo "\n-- version_conflict expected code constant --\n";
assertSame(
    'version_conflict',
    CatalogVersionGate::DECISION_CONFLICT,
    'conflict decision code is version_conflict',
);

echo "\n=== Summary: passed={$passed} failed={$failed} ===\n";
exit($failed === 0 ? 0 : 1);
