<?php

declare(strict_types=1);

/**
 * Phase C — Product Units Update Contract v2 wiring.
 *
 * Run: php cloud/api/src/Modules/Sync/test_phase_c_units_contract_unit.php
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
use MizaCloud\Modules\Sync\Support\CatalogFullToPatchAdapter;
use MizaCloud\Modules\Sync\Support\CatalogPatchOrchestrator;
use MizaCloud\Modules\Sync\Support\CatalogVersionGate;
use MizaCloud\Modules\Sync\Validators\ProductUnitsPushValidator;

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

function makeStack(): CatalogPatchOrchestrator
{
    $root = dirname(__DIR__, 3) . '/contracts/field-dictionary';
    $dict = (new FieldDictionaryLoader($root))->load('1.0.0');
    $meta = new FieldMetadataProvider($dict);
    $engine = new ChangeDetectionEngine($meta);
    $builder = new PatchBuilder($engine, $meta);
    $validator = new PatchValidator($meta, $engine);
    $adapter = new CatalogFullToPatchAdapter($engine, $builder, $meta);

    return new CatalogPatchOrchestrator($meta, $engine, $builder, $validator, $adapter);
}

/**
 * @param array<string, mixed> $server
 * @param array<string, mixed> $fields
 * @return array<string, mixed>
 */
function applyPatchInMemory(array $server, array $fields, int $newVersion): array
{
    $out = $server;
    foreach ($fields as $k => $v) {
        $out[$k] = $v;
    }
    $out['row_version'] = $newVersion;

    return $out;
}

$orch = makeStack();
$entityId = 'e500e840-e29b-41d4-a716-446655440050';

$server = [
    'name' => 'Kilogram',
    'row_version' => 5,
    'deleted_at' => null,
];

echo "=== Phase C Units Update Contract v2 ===\n\n";

echo "-- Native patch / unchanged fields omitted --\n";
$plan = $orch->planUpdate(
    'product_unit',
    PatchValidator::PATH_PRODUCT_UNIT_CATALOG_PATCH,
    $entityId,
    'patch',
    [
        'operation_id' => 'op-name-1',
        'base_row_version' => 5,
        'changed_fields' => ['name'],
        'dictionary_version' => '1.0.0',
    ],
    ['name' => 'Kg'],
    $server,
    6,
);
assertSame(CatalogVersionGate::DECISION_APPLY, $plan['decision'], 'native patch apply');
assertSame(['name' => 'Kg'], $plan['normalized_changed_fields'], 'only name in plan');
assertSame('native_patch', $plan['source'], 'source native_patch');

$after = applyPatchInMemory($server, $plan['normalized_changed_fields'], $plan['new_row_version']);
assertSame('Kg', $after['name'], 'name updated');
assertSame(6, $after['row_version'], 'row_version bumped server+1');

echo "\n-- Higher Version Lost Update (native patch) --\n";
$serverAfterA = $server;
$serverAfterA['name'] = 'Kilo';
$serverAfterA['row_version'] = 6;

$stale = $orch->planUpdate(
    'product_unit',
    PatchValidator::PATH_PRODUCT_UNIT_CATALOG_PATCH,
    $entityId,
    'patch',
    [
        'operation_id' => 'op-b-stale',
        'base_row_version' => 5,
        'changed_fields' => ['name'],
        'dictionary_version' => '1.0.0',
    ],
    ['name' => 'KG'],
    $serverAfterA,
    7,
);
assertSame(CatalogVersionGate::DECISION_CONFLICT, $stale['decision'], 'stale base => conflict (no blind write)');

$rebased = $orch->planUpdate(
    'product_unit',
    PatchValidator::PATH_PRODUCT_UNIT_CATALOG_PATCH,
    $entityId,
    'patch',
    [
        'operation_id' => 'op-b-rebase',
        'base_row_version' => 6,
        'changed_fields' => ['name'],
        'dictionary_version' => '1.0.0',
    ],
    ['name' => 'KG'],
    $serverAfterA,
    7,
);
assertSame(CatalogVersionGate::DECISION_APPLY, $rebased['decision'], 'rebased patch apply');
$merged = applyPatchInMemory($serverAfterA, $rebased['normalized_changed_fields'], $rebased['new_row_version']);
assertSame('KG', $merged['name'], 'Device B name applied after rebase');

echo "\n-- Forbid Full Entity on patch path --\n";
$fullForbidden = $orch->planUpdate(
    'product_unit',
    PatchValidator::PATH_PRODUCT_UNIT_CATALOG_PATCH,
    $entityId,
    'patch',
    [
        'operation_id' => 'op-full-forbidden',
        'base_row_version' => 5,
        'changed_fields' => ['name'],
        'dictionary_version' => '1.0.0',
    ],
    [
        'name' => 'Kg',
        'extra_field' => 'nope',
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

echo "\n-- Full → Patch Adapter --\n";
$fullPayload = ['name' => 'Kilogram'];
$adaptedSame = $orch->planUpdate(
    'product_unit',
    PatchValidator::PATH_PRODUCT_UNIT_CATALOG_PATCH,
    $entityId,
    'update',
    ['operation_id' => 'op-legacy-noop'],
    $fullPayload,
    $server,
    5,
);
assertSame('full_to_patch_adapter', $adaptedSame['source'], 'adapter source');
assertSame(CatalogVersionGate::DECISION_NO_OP, $adaptedSame['decision'], 'identical full payload => no_op');

$adapted = $orch->planUpdate(
    'product_unit',
    PatchValidator::PATH_PRODUCT_UNIT_CATALOG_PATCH,
    $entityId,
    'update',
    ['operation_id' => 'op-legacy-1', 'outbox_id' => 'ob-1'],
    ['name' => 'Piece'],
    $server,
    6,
);
assertSame('full_to_patch_adapter', $adapted['source'], 'adapter source on change');
assertSame(CatalogVersionGate::DECISION_APPLY, $adapted['decision'], 'adapter apply when base==server');
assertSame(['name' => 'Piece'], $adapted['normalized_changed_fields'], 'adapter only emits real diffs');

$staleLegacy = $orch->planUpdate(
    'product_unit',
    PatchValidator::PATH_PRODUCT_UNIT_CATALOG_PATCH,
    $entityId,
    'update',
    ['operation_id' => 'op-legacy-stale'],
    ['name' => 'Box'],
    $server,
    2,
);
assertSame(CatalogVersionGate::DECISION_CONFLICT, $staleLegacy['decision'], 'legacy stale client_row_version => conflict');

echo "\n-- Field Dictionary validation --\n";
$unknown = $orch->planUpdate(
    'product_unit',
    PatchValidator::PATH_PRODUCT_UNIT_CATALOG_PATCH,
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

$badDict = $orch->planUpdate(
    'product_unit',
    PatchValidator::PATH_PRODUCT_UNIT_CATALOG_PATCH,
    $entityId,
    'patch',
    [
        'operation_id' => 'op-dict',
        'base_row_version' => 5,
        'changed_fields' => ['name' => 'X'],
        'dictionary_version' => '9.9.9',
    ],
    ['changed_fields' => ['name' => 'X']],
    $server,
    6,
);
assertSame('validation_error', $badDict['decision'], 'dictionary version mismatch');

$nullName = $orch->planUpdate(
    'product_unit',
    PatchValidator::PATH_PRODUCT_UNIT_CATALOG_PATCH,
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

$nameSame = $orch->planUpdate(
    'product_unit',
    PatchValidator::PATH_PRODUCT_UNIT_CATALOG_PATCH,
    $entityId,
    'patch',
    [
        'operation_id' => 'op-name-same',
        'base_row_version' => 5,
        'changed_fields' => ['name' => 'Kilogram'],
        'dictionary_version' => '1.0.0',
    ],
    ['changed_fields' => ['name' => 'Kilogram']],
    $server,
    5,
);
assertSame(CatalogVersionGate::DECISION_NO_OP, $nameSame['decision'], 'unchanged name => no_op');

$invalidChanged = $orch->planUpdate(
    'product_unit',
    PatchValidator::PATH_PRODUCT_UNIT_CATALOG_PATCH,
    $entityId,
    'patch',
    [
        'operation_id' => 'op-bad-cf',
        'base_row_version' => 5,
        'dictionary_version' => '1.0.0',
    ],
    ['name' => 'X'],
    $server,
    6,
);
assertSame('validation_error', $invalidChanged['decision'], 'missing changed_fields on native patch');

echo "\n-- ProductUnitsPushValidator --\n";
$vLegacy = new ProductUnitsPushValidator([
    'company_id' => '550e8400-e29b-41d4-a716-446655440000',
    'branch_id' => '660e8400-e29b-41d4-a716-446655440001',
    'device_id' => '770e8400-e29b-41d4-a716-446655440002',
    'batch_id' => '880e8400-e29b-41d4-a716-446655440003',
    'events' => [[
        'outbox_id' => 'o1',
        'entity_type' => 'product_unit',
        'entity_id' => $entityId,
        'operation' => 'update',
        'payload_json' => ['name' => 'Kilogram'],
        'idempotency_key' => 'k1',
        'client_row_version' => 2,
    ]],
]);
assertFalse($vLegacy->failed(), 'legacy update still validates (migration BC)');

$vPatch = new ProductUnitsPushValidator([
    'company_id' => '550e8400-e29b-41d4-a716-446655440000',
    'branch_id' => '660e8400-e29b-41d4-a716-446655440001',
    'device_id' => '770e8400-e29b-41d4-a716-446655440002',
    'batch_id' => '880e8400-e29b-41d4-a716-446655440003',
    'events' => [[
        'outbox_id' => 'o2',
        'entity_type' => 'product_unit',
        'entity_id' => $entityId,
        'operation' => 'patch',
        'base_row_version' => 5,
        'changed_fields' => ['name'],
        'payload_json' => ['name' => 'Kg'],
        'idempotency_key' => 'k2',
        'client_row_version' => 6,
    ]],
]);
assertFalse($vPatch->failed(), 'native patch validates');

$vPatchBad = new ProductUnitsPushValidator([
    'company_id' => '550e8400-e29b-41d4-a716-446655440000',
    'branch_id' => '660e8400-e29b-41d4-a716-446655440001',
    'device_id' => '770e8400-e29b-41d4-a716-446655440002',
    'batch_id' => '880e8400-e29b-41d4-a716-446655440003',
    'events' => [[
        'outbox_id' => 'o3',
        'entity_type' => 'product_unit',
        'entity_id' => $entityId,
        'operation' => 'patch',
        'payload_json' => ['name' => 'Kg'],
        'idempotency_key' => 'k3',
    ]],
]);
assertTrue($vPatchBad->failed(), 'patch without base/changed_fields fails validation');

echo "\n-- Integration pipeline --\n";
$adapter = $orch->adapter();
$built = $adapter->adapt('product_unit', $entityId, $server, [
    'name' => 'Litre',
], 'op-int-1');
$vr = $orch->validator()->validate($built, PatchValidator::PATH_PRODUCT_UNIT_CATALOG_PATCH);
assertSame(PatchValidator::RESULT_VALID, $vr['status'], 'integration validator');
$decision = CatalogVersionGate::decidePatch(5, (int) $built['base_row_version'], $built['changed_fields'] === []);
assertSame(CatalogVersionGate::DECISION_APPLY, $decision, 'integration gate');
$applied = applyPatchInMemory($server, $vr['normalized_changed_fields'] ?? [], 6);
assertSame('Litre', $applied['name'], 'integration applied name');
assertSame(6, $applied['row_version'], 'integration version');

$mapPlan = $orch->planUpdate(
    'product_unit',
    PatchValidator::PATH_PRODUCT_UNIT_CATALOG_PATCH,
    $entityId,
    'update',
    [
        'contract_version' => 2,
        'operation_id' => 'op-map',
        'base_row_version' => 5,
        'changed_fields' => ['name' => 'Meter'],
        'dictionary_version' => '1.0.0',
    ],
    [],
    $server,
    6,
);
assertSame('native_patch', $mapPlan['source'], 'contract_version 2 => native');
assertSame(['name' => 'Meter'], $mapPlan['normalized_changed_fields'], 'map-form name patch');

echo "\n-- Migration / Offline / Replay / Retry / Perf --\n";
assertSame('full_to_patch_adapter', $adapted['source'], 'migration: full update uses adapter');
assertFalse($vLegacy->failed(), 'migration BC: legacy validator accepts full update');
assertSame(CatalogVersionGate::DECISION_CONFLICT, $stale['decision'], 'offline: stale base conflicts until rebase');
assertSame('op-b-rebase', $rebased['patch']['operation_id'] ?? null, 'replay: operation_id preserved on rebased patch');
assertSame(CatalogVersionGate::DECISION_APPLY, $rebased['decision'], 'retry: rebase after conflict applies');
$t0 = hrtime(true);
for ($i = 0; $i < 200; $i++) {
    $orch->planUpdate(
        'product_unit',
        PatchValidator::PATH_PRODUCT_UNIT_CATALOG_PATCH,
        $entityId,
        'patch',
        [
            'operation_id' => "op-perf-{$i}",
            'base_row_version' => 5,
            'changed_fields' => ['name'],
            'dictionary_version' => '1.0.0',
        ],
        ['name' => 'U' . ($i % 3)],
        $server,
        6,
    );
}
$elapsedMs = (hrtime(true) - $t0) / 1e6;
assertTrue($elapsedMs < 2000.0, 'perf: 200 planUpdate calls under 2s');

echo "\n=== Results: {$passed} passed, {$failed} failed ===\n";
exit($failed > 0 ? 1 : 0);
