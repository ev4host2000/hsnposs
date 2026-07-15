<?php

declare(strict_types=1);

/**
 * Phase B — Products Update Contract v2 wiring (pure logic + integration without DB).
 *
 * Run: php cloud/api/src/Modules/Sync/test_phase_b_products_contract_unit.php
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

use MizaCloud\Modules\Sync\Contract\ChangeDetectionEngine;
use MizaCloud\Modules\Sync\Contract\FieldDictionaryLoader;
use MizaCloud\Modules\Sync\Contract\FieldMetadataProvider;
use MizaCloud\Modules\Sync\Contract\PatchBuilder;
use MizaCloud\Modules\Sync\Contract\PatchValidator;
use MizaCloud\Modules\Sync\Support\CatalogVersionGate;
use MizaCloud\Modules\Sync\Support\ProductFullToPatchAdapter;
use MizaCloud\Modules\Sync\Support\ProductPatchOrchestrator;
use MizaCloud\Modules\Sync\Validators\ProductsPushValidator;

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

function assertTrue(bool $cond, string $msg): void
{
    assertSame(true, $cond, $msg);
}

function assertFalse(bool $cond, string $msg): void
{
    assertSame(false, $cond, $msg);
}

function expectException(callable $fn, string $contains, string $msg): void
{
    global $failed, $passed;
    try {
        $fn();
        ++$failed;
        fwrite(STDERR, "FAIL: {$msg}\n  expected exception containing: {$contains}\n");
    } catch (\Throwable $e) {
        if (!str_contains($e->getMessage(), $contains)) {
            ++$failed;
            fwrite(STDERR, "FAIL: {$msg}\n  expected: {$contains}\n  got: {$e->getMessage()}\n");
            return;
        }
        ++$passed;
        echo "OK: {$msg}\n";
    }
}

function makeStack(): ProductPatchOrchestrator
{
    $root = dirname(__DIR__, 3) . '/contracts/field-dictionary';
    $dict = (new FieldDictionaryLoader($root))->load('1.0.0');
    $meta = new FieldMetadataProvider($dict);
    $engine = new ChangeDetectionEngine($meta);
    $builder = new PatchBuilder($engine, $meta);
    $validator = new PatchValidator($meta, $engine);
    $adapter = new ProductFullToPatchAdapter($engine, $builder, $meta);

    return new ProductPatchOrchestrator($meta, $engine, $builder, $validator, $adapter);
}

/**
 * In-memory apply used for integration tests (mirrors repository patch semantics).
 *
 * @param array<string, mixed> $server
 * @param array<string, mixed> $fields
 * @return array<string, mixed>
 */
function applyPatchInMemory(array $server, array $fields, int $newVersion): array
{
    $forbidden = ['stock_qty'];
    foreach ($fields as $k => $_) {
        if (in_array($k, $forbidden, true)) {
            throw new RuntimeException('Forbidden field written: ' . $k);
        }
    }
    $out = $server;
    foreach ($fields as $k => $v) {
        $out[$k] = $v;
    }
    $out['row_version'] = $newVersion;

    return $out;
}

$orch = makeStack();
$entityId = 'a100e840-e29b-41d4-a716-446655440020';

$server = [
    'name' => 'Milk',
    'sale_price' => '6.5000',
    'cost_price' => '5.0000',
    'stock_qty' => '48.0000',
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

echo "=== Phase B Products Update Contract v2 ===\n\n";

// ---------------------------------------------------------------------------
// 1) Native patch — only changed fields
// ---------------------------------------------------------------------------
echo "-- Native patch / unchanged fields omitted --\n";
$plan = $orch->planUpdate(
    $entityId,
    'patch',
    [
        'operation_id' => 'op-price-1',
        'base_row_version' => 5,
        'changed_fields' => ['sale_price'],
        'dictionary_version' => '1.0.0',
    ],
    ['sale_price' => 9.0],
    $server,
    6,
);
assertSame(CatalogVersionGate::DECISION_APPLY, $plan['decision'], 'native patch apply');
assertSame(['sale_price' => '9.0000'], $plan['normalized_changed_fields'], 'only sale_price in plan');
assertFalse(isset($plan['normalized_changed_fields']['name']), 'name not in changed_fields');
assertSame('native_patch', $plan['source'], 'source native_patch');

$after = applyPatchInMemory($server, $plan['normalized_changed_fields'], $plan['new_row_version']);
assertSame('Milk', $after['name'], 'name preserved after price patch');
assertSame('9.0000', $after['sale_price'], 'price updated');
assertSame('48.0000', $after['stock_qty'], 'stock untouched');
assertSame(6, $after['row_version'], 'row_version bumped server+1');

// ---------------------------------------------------------------------------
// 2) Higher Version Lost Update — FIXED by native patch
// ---------------------------------------------------------------------------
echo "\n-- Higher Version Lost Update (native patch) --\n";
// Cloud v5 name=NewName (Device A already applied). Device B offline edited price only.
$serverAfterA = $server;
$serverAfterA['name'] = 'NewName';
$serverAfterA['row_version'] = 6;

// Device B sends ONLY price change based on base=5 — conflict (stale base)
$stale = $orch->planUpdate(
    $entityId,
    'patch',
    [
        'operation_id' => 'op-b-stale',
        'base_row_version' => 5,
        'changed_fields' => ['sale_price'],
        'dictionary_version' => '1.0.0',
    ],
    ['sale_price' => 7.5],
    $serverAfterA,
    7,
);
assertSame(CatalogVersionGate::DECISION_CONFLICT, $stale['decision'], 'stale base => conflict (no blind write)');

// Device B pulls, rebases to base=6, patches price only — name preserved
$rebased = $orch->planUpdate(
    $entityId,
    'patch',
    [
        'operation_id' => 'op-b-rebase',
        'base_row_version' => 6,
        'changed_fields' => ['sale_price'],
        'dictionary_version' => '1.0.0',
    ],
    ['sale_price' => 7.5],
    $serverAfterA,
    7,
);
assertSame(CatalogVersionGate::DECISION_APPLY, $rebased['decision'], 'rebased patch apply');
$merged = applyPatchInMemory($serverAfterA, $rebased['normalized_changed_fields'], $rebased['new_row_version']);
assertSame('NewName', $merged['name'], 'HVLU fixed: Device A name preserved');
assertSame('7.5000', $merged['sale_price'], 'Device B price applied');

// ---------------------------------------------------------------------------
// 3) Forbid full entity on patch path
// ---------------------------------------------------------------------------
echo "\n-- Forbid Full Entity on patch path --\n";
$fullForbidden = $orch->planUpdate(
    $entityId,
    'patch',
    [
        'operation_id' => 'op-full-forbidden',
        'base_row_version' => 5,
        'changed_fields' => ['sale_price'],
        'dictionary_version' => '1.0.0',
    ],
    [
        'sale_price' => 9.0,
        'name' => 'ShouldNotAppear',
        'cost_price' => 1,
        'stock_qty' => 99,
    ],
    $server,
    6,
);
assertSame('validation_error', $fullForbidden['decision'], 'extra payload fields rejected on native patch');
assertTrue(
    (bool) array_filter(
        $fullForbidden['errors'],
        static fn ($e) => str_contains($e, 'Full entity payload is forbidden'),
    ),
    'forbidden full-entity error message',
);

// ---------------------------------------------------------------------------
// 4) Full → Patch Adapter (backward compatibility)
// ---------------------------------------------------------------------------
echo "\n-- Full → Patch Adapter --\n";
$fullPayload = [
    'name' => 'Milk',
    'sale_price' => 9.0,
    'cost_price' => 5.0,
    'stock_qty' => 999.0, // must not enter changed_fields
    'barcode' => '123',
    'unit_name' => 'pcs',
    'image_url' => 'https://cdn/a.png',
    'is_hidden' => false,
    'is_frozen' => false,
    'is_service' => false,
    'sort_order' => 0,
];
$adapted = $orch->planUpdate(
    $entityId,
    'update',
    ['operation_id' => 'op-legacy-1', 'outbox_id' => 'ob-1'],
    $fullPayload,
    $server,
    6,
);
assertSame('full_to_patch_adapter', $adapted['source'], 'adapter source');
assertSame(CatalogVersionGate::DECISION_APPLY, $adapted['decision'], 'adapter apply when base==server');
assertSame(['sale_price' => '9.0000'], $adapted['normalized_changed_fields'], 'adapter only emits real diffs');
assertFalse(isset($adapted['normalized_changed_fields']['stock_qty']), 'adapter excludes stock_qty');
assertFalse(isset($adapted['normalized_changed_fields']['name']), 'adapter omits unchanged name');

// Absent image_url must not clear image
$noImagePayload = $fullPayload;
unset($noImagePayload['image_url']);
$noImagePayload['sale_price'] = 6.5;
$noImagePlan = $orch->planUpdate(
    $entityId,
    'update',
    ['operation_id' => 'op-legacy-img'],
    $noImagePayload,
    $server,
    5,
);
assertSame(CatalogVersionGate::DECISION_NO_OP, $noImagePlan['decision'], 'identical full payload => no_op');
assertFalse(isset($noImagePlan['patch']['changed_fields']['image_url']), 'absent image not treated as clear');

// Stale client_row_version (< server) => conflict via adapter transition policy
$staleLegacy = $orch->planUpdate(
    $entityId,
    'update',
    ['operation_id' => 'op-legacy-stale'],
    array_merge($fullPayload, ['sale_price' => 10]),
    $server,
    2,
);
assertSame(CatalogVersionGate::DECISION_CONFLICT, $staleLegacy['decision'], 'legacy stale client_row_version => conflict');

// Adapter map form: image change only
$imgPayload = $fullPayload;
$imgPayload['image_url'] = 'https://cdn/b.png';
$imgPayload['sale_price'] = 6.5;
$imgPlan = $orch->planUpdate(
    $entityId,
    'update',
    ['operation_id' => 'op-legacy-img2'],
    $imgPayload,
    $server,
    6,
);
assertSame(['image_url' => 'https://cdn/b.png'], $imgPlan['normalized_changed_fields'], 'adapter image-only change');

// ---------------------------------------------------------------------------
// 5) Field Dictionary validation
// ---------------------------------------------------------------------------
echo "\n-- Field Dictionary validation --\n";
$forbidden = $orch->planUpdate(
    $entityId,
    'patch',
    [
        'operation_id' => 'op-stock',
        'base_row_version' => 5,
        'changed_fields' => ['stock_qty' => '1'],
        'dictionary_version' => '1.0.0',
    ],
    ['changed_fields' => ['stock_qty' => '1']],
    $server,
    6,
);
assertSame('validation_error', $forbidden['decision'], 'stock_qty forbidden/not patchable');
assertTrue(
    count(array_filter($forbidden['errors'], static fn ($e) => str_contains($e, 'not patchable') || str_contains($e, 'forbidden'))) >= 1,
    'stock_qty error mentions patchable/forbidden',
);

$unknown = $orch->planUpdate(
    $entityId,
    'patch',
    [
        'operation_id' => 'op-unknown',
        'base_row_version' => 5,
        'changed_fields' => ['not_a_field' => 'x'],
        'dictionary_version' => '1.0.0',
    ],
    ['changed_fields' => ['not_a_field' => 'x']],
    $server,
    6,
);
assertSame('validation_error', $unknown['decision'], 'unknown field rejected');
assertTrue(
    (bool) array_filter($unknown['errors'], static fn ($e) => str_contains($e, 'Unknown field')),
    'unknown field error',
);

$badDict = $orch->planUpdate(
    $entityId,
    'patch',
    [
        'operation_id' => 'op-dict',
        'base_row_version' => 5,
        'changed_fields' => ['sale_price' => 1],
        'dictionary_version' => '9.9.9',
    ],
    ['changed_fields' => ['sale_price' => 1]],
    $server,
    6,
);
assertSame('validation_error', $badDict['decision'], 'dictionary version mismatch');
assertTrue(
    (bool) array_filter($badDict['errors'], static fn ($e) => str_contains($e, 'dictionary_version mismatch')),
    'dictionary mismatch error',
);

$nullName = $orch->planUpdate(
    $entityId,
    'patch',
    [
        'operation_id' => 'op-null',
        'base_row_version' => 5,
        'changed_fields' => ['name' => null],
        'dictionary_version' => '1.0.0',
    ],
    ['changed_fields' => ['name' => null]],
    $server,
    6,
);
assertSame('validation_error', $nullName['decision'], 'nullable=false name rejects null');

// Decimal comparison (scale)
$decSame = $orch->planUpdate(
    $entityId,
    'patch',
    [
        'operation_id' => 'op-dec-same',
        'base_row_version' => 5,
        'changed_fields' => ['sale_price' => 6.5],
        'dictionary_version' => '1.0.0',
    ],
    ['changed_fields' => ['sale_price' => 6.5]],
    $server,
    5,
);
assertSame(CatalogVersionGate::DECISION_NO_OP, $decSame['decision'], 'decimal 6.5 equals 6.5000 => no_op');

$decDiff = $orch->planUpdate(
    $entityId,
    'patch',
    [
        'operation_id' => 'op-dec-diff',
        'base_row_version' => 5,
        'changed_fields' => ['sale_price' => '6.5001'],
        'dictionary_version' => '1.0.0',
    ],
    ['changed_fields' => ['sale_price' => '6.5001']],
    $server,
    6,
);
assertSame(CatalogVersionGate::DECISION_APPLY, $decDiff['decision'], 'decimal scale difference => apply');
assertSame('6.5001', $decDiff['normalized_changed_fields']['sale_price'], 'decimal normalized');

// Nullable barcode null clear
$barNull = $orch->planUpdate(
    $entityId,
    'patch',
    [
        'operation_id' => 'op-bar',
        'base_row_version' => 5,
        'changed_fields' => ['barcode' => null],
        'dictionary_version' => '1.0.0',
    ],
    ['changed_fields' => ['barcode' => null]],
    $server,
    6,
);
assertSame(CatalogVersionGate::DECISION_APPLY, $barNull['decision'], 'nullable barcode null allowed');
assertSame(null, $barNull['normalized_changed_fields']['barcode'], 'barcode cleared');

// Image empty_as_null
$imgClear = $orch->planUpdate(
    $entityId,
    'patch',
    [
        'operation_id' => 'op-img-clear',
        'base_row_version' => 5,
        'changed_fields' => ['image_url' => ''],
        'dictionary_version' => '1.0.0',
    ],
    ['changed_fields' => ['image_url' => '']],
    $server,
    6,
);
assertSame(CatalogVersionGate::DECISION_APPLY, $imgClear['decision'], 'image blank => null change');
assertSame(null, $imgClear['normalized_changed_fields']['image_url'], 'image normalized null');

// ---------------------------------------------------------------------------
// 6) Push validator BC + patch
// ---------------------------------------------------------------------------
echo "\n-- ProductsPushValidator --\n";
$vLegacy = new ProductsPushValidator([
    'company_id' => '550e8400-e29b-41d4-a716-446655440000',
    'branch_id' => '660e8400-e29b-41d4-a716-446655440001',
    'device_id' => '770e8400-e29b-41d4-a716-446655440002',
    'batch_id' => '880e8400-e29b-41d4-a716-446655440003',
    'events' => [[
        'outbox_id' => 'o1',
        'entity_type' => 'product',
        'entity_id' => $entityId,
        'operation' => 'update',
        'payload_json' => ['name' => 'Milk', 'sale_price' => 1],
        'idempotency_key' => 'k1',
        'client_row_version' => 2,
    ]],
]);
assertFalse($vLegacy->failed(), 'legacy update still validates');

$vPatch = new ProductsPushValidator([
    'company_id' => '550e8400-e29b-41d4-a716-446655440000',
    'branch_id' => '660e8400-e29b-41d4-a716-446655440001',
    'device_id' => '770e8400-e29b-41d4-a716-446655440002',
    'batch_id' => '880e8400-e29b-41d4-a716-446655440003',
    'events' => [[
        'outbox_id' => 'o2',
        'entity_type' => 'product',
        'entity_id' => $entityId,
        'operation' => 'patch',
        'base_row_version' => 5,
        'changed_fields' => ['sale_price'],
        'payload_json' => ['sale_price' => 9],
        'idempotency_key' => 'k2',
        'client_row_version' => 6,
    ]],
]);
assertFalse($vPatch->failed(), 'native patch validates without name');

$vPatchBad = new ProductsPushValidator([
    'company_id' => '550e8400-e29b-41d4-a716-446655440000',
    'branch_id' => '660e8400-e29b-41d4-a716-446655440001',
    'device_id' => '770e8400-e29b-41d4-a716-446655440002',
    'batch_id' => '880e8400-e29b-41d4-a716-446655440003',
    'events' => [[
        'outbox_id' => 'o3',
        'entity_type' => 'product',
        'entity_id' => $entityId,
        'operation' => 'patch',
        'payload_json' => ['sale_price' => 9],
        'idempotency_key' => 'k3',
    ]],
]);
assertTrue($vPatchBad->failed(), 'patch without base/changed_fields fails validation');

// ---------------------------------------------------------------------------
// 7) Integration: detect → build → validate → gate → apply (in-memory)
// ---------------------------------------------------------------------------
echo "\n-- Integration pipeline --\n";
$adapter = $orch->adapter();
$built = $adapter->adapt($entityId, $server, [
    'name' => 'Milk',
    'sale_price' => 8,
    'cost_price' => 5,
    'barcode' => '123',
    'unit_name' => 'pcs',
    'is_hidden' => false,
    'is_frozen' => false,
    'is_service' => false,
    'sort_order' => 0,
], 'op-int-1');
$vr = $orch->validator()->validate($built, PatchValidator::PATH_PRODUCT_CATALOG_PATCH);
assertSame(PatchValidator::RESULT_VALID, $vr['status'], 'integration validator');
$decision = CatalogVersionGate::decidePatch(5, (int) $built['base_row_version'], $built['changed_fields'] === []);
assertSame(CatalogVersionGate::DECISION_APPLY, $decision, 'integration gate');
$applied = applyPatchInMemory($server, $vr['normalized_changed_fields'] ?? [], 6);
assertSame('8.0000', $applied['sale_price'], 'integration applied price');
assertSame('Milk', $applied['name'], 'integration preserved name');
assertSame(6, $applied['row_version'], 'integration version');

// Map-form changed_fields on event
$mapPlan = $orch->planUpdate(
    $entityId,
    'update',
    [
        'contract_version' => 2,
        'operation_id' => 'op-map',
        'base_row_version' => 5,
        'changed_fields' => ['name' => 'Yogurt'],
        'dictionary_version' => '1.0.0',
    ],
    [],
    $server,
    6,
);
assertSame('native_patch', $mapPlan['source'], 'contract_version 2 => native');
assertSame(['name' => 'Yogurt'], $mapPlan['normalized_changed_fields'], 'map-form name patch');

echo "\n=== Results: {$passed} passed, {$failed} failed ===\n";
exit($failed > 0 ? 1 : 0);
