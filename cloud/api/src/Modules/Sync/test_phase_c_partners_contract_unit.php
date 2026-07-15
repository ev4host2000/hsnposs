<?php

declare(strict_types=1);

/**
 * Phase C — Partners Update Contract v2 wiring (customer + short supplier).
 *
 * Run: php cloud/api/src/Modules/Sync/test_phase_c_partners_contract_unit.php
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
use MizaCloud\Modules\Sync\Validators\CustomersPushValidator;
use MizaCloud\Modules\Sync\Validators\SuppliersPushValidator;

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
$entityId = 'b200e840-e29b-41d4-a716-446655440030';
$supplierId = 'c300e840-e29b-41d4-a716-446655440031';

$server = [
    'name' => 'Acme Customer',
    'phone' => '0500000000',
    'address' => 'Riyadh',
    'notes' => null,
    'partner_number' => '1',
    'credit_limit' => '1000.0000',
    'overdue_alert_days' => 30,
    'customer_group_id' => null,
    'row_version' => 5,
    'deleted_at' => null,
];

echo "=== Phase C Partners Update Contract v2 ===\n\n";

// ---------------------------------------------------------------------------
// 1) Native patch — only changed fields
// ---------------------------------------------------------------------------
echo "-- Native patch / unchanged fields omitted --\n";
$plan = $orch->planUpdate(
    'customer',
    PatchValidator::PATH_CUSTOMER_CATALOG_PATCH,
    $entityId,
    'patch',
    [
        'operation_id' => 'op-phone-1',
        'base_row_version' => 5,
        'changed_fields' => ['phone'],
        'dictionary_version' => '1.0.0',
    ],
    ['phone' => '0551112233'],
    $server,
    6,
);
assertSame(CatalogVersionGate::DECISION_APPLY, $plan['decision'], 'native patch apply');
assertSame(['phone' => '0551112233'], $plan['normalized_changed_fields'], 'only phone in plan');
assertFalse(isset($plan['normalized_changed_fields']['name']), 'name not in changed_fields');
assertSame('native_patch', $plan['source'], 'source native_patch');

$after = applyPatchInMemory($server, $plan['normalized_changed_fields'], $plan['new_row_version']);
assertSame('Acme Customer', $after['name'], 'name preserved after phone patch');
assertSame('0551112233', $after['phone'], 'phone updated');
assertSame('1000.0000', $after['credit_limit'], 'credit_limit untouched');
assertSame(6, $after['row_version'], 'row_version bumped server+1');

// ---------------------------------------------------------------------------
// 2) Higher Version Lost Update — FIXED by native patch
// ---------------------------------------------------------------------------
echo "\n-- Higher Version Lost Update (native patch) --\n";
$serverAfterA = $server;
$serverAfterA['name'] = 'NewName';
$serverAfterA['row_version'] = 6;

$stale = $orch->planUpdate(
    'customer',
    PatchValidator::PATH_CUSTOMER_CATALOG_PATCH,
    $entityId,
    'patch',
    [
        'operation_id' => 'op-b-stale',
        'base_row_version' => 5,
        'changed_fields' => ['phone'],
        'dictionary_version' => '1.0.0',
    ],
    ['phone' => '0559998877'],
    $serverAfterA,
    7,
);
assertSame(CatalogVersionGate::DECISION_CONFLICT, $stale['decision'], 'stale base => conflict (no blind write)');

$rebased = $orch->planUpdate(
    'customer',
    PatchValidator::PATH_CUSTOMER_CATALOG_PATCH,
    $entityId,
    'patch',
    [
        'operation_id' => 'op-b-rebase',
        'base_row_version' => 6,
        'changed_fields' => ['phone'],
        'dictionary_version' => '1.0.0',
    ],
    ['phone' => '0559998877'],
    $serverAfterA,
    7,
);
assertSame(CatalogVersionGate::DECISION_APPLY, $rebased['decision'], 'rebased patch apply');
$merged = applyPatchInMemory($serverAfterA, $rebased['normalized_changed_fields'], $rebased['new_row_version']);
assertSame('NewName', $merged['name'], 'HVLU fixed: Device A name preserved');
assertSame('0559998877', $merged['phone'], 'Device B phone applied');

// ---------------------------------------------------------------------------
// 3) Forbid full entity on patch path
// ---------------------------------------------------------------------------
echo "\n-- Forbid Full Entity on patch path --\n";
$fullForbidden = $orch->planUpdate(
    'customer',
    PatchValidator::PATH_CUSTOMER_CATALOG_PATCH,
    $entityId,
    'patch',
    [
        'operation_id' => 'op-full-forbidden',
        'base_row_version' => 5,
        'changed_fields' => ['phone'],
        'dictionary_version' => '1.0.0',
    ],
    [
        'phone' => '0551112233',
        'name' => 'ShouldNotAppear',
        'credit_limit' => 1,
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
    'name' => 'Acme Customer',
    'phone' => '0551112233',
    'address' => 'Riyadh',
    'partner_number' => '1',
    'credit_limit' => 1000.0,
    'overdue_alert_days' => 30,
];
$adapted = $orch->planUpdate(
    'customer',
    PatchValidator::PATH_CUSTOMER_CATALOG_PATCH,
    $entityId,
    'update',
    ['operation_id' => 'op-legacy-1', 'outbox_id' => 'ob-1'],
    $fullPayload,
    $server,
    6,
);
assertSame('full_to_patch_adapter', $adapted['source'], 'adapter source');
assertSame(CatalogVersionGate::DECISION_APPLY, $adapted['decision'], 'adapter apply when base==server');
assertSame(['phone' => '0551112233'], $adapted['normalized_changed_fields'], 'adapter only emits real diffs');
assertFalse(isset($adapted['normalized_changed_fields']['name']), 'adapter omits unchanged name');

$noChangePayload = $fullPayload;
$noChangePayload['phone'] = '0500000000';
$noOpPlan = $orch->planUpdate(
    'customer',
    PatchValidator::PATH_CUSTOMER_CATALOG_PATCH,
    $entityId,
    'update',
    ['operation_id' => 'op-legacy-noop'],
    $noChangePayload,
    $server,
    5,
);
assertSame(CatalogVersionGate::DECISION_NO_OP, $noOpPlan['decision'], 'identical full payload => no_op');

$staleLegacy = $orch->planUpdate(
    'customer',
    PatchValidator::PATH_CUSTOMER_CATALOG_PATCH,
    $entityId,
    'update',
    ['operation_id' => 'op-legacy-stale'],
    array_merge($fullPayload, ['phone' => '0550001111']),
    $server,
    2,
);
assertSame(CatalogVersionGate::DECISION_CONFLICT, $staleLegacy['decision'], 'legacy stale client_row_version => conflict');

// ---------------------------------------------------------------------------
// 5) Field Dictionary validation
// ---------------------------------------------------------------------------
echo "\n-- Field Dictionary validation --\n";
$unknown = $orch->planUpdate(
    'customer',
    PatchValidator::PATH_CUSTOMER_CATALOG_PATCH,
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
    'customer',
    PatchValidator::PATH_CUSTOMER_CATALOG_PATCH,
    $entityId,
    'patch',
    [
        'operation_id' => 'op-dict',
        'base_row_version' => 5,
        'changed_fields' => ['phone' => '1'],
        'dictionary_version' => '9.9.9',
    ],
    ['changed_fields' => ['phone' => '1']],
    $server,
    6,
);
assertSame('validation_error', $badDict['decision'], 'dictionary version mismatch');
assertTrue(
    (bool) array_filter($badDict['errors'], static fn ($e) => str_contains($e, 'dictionary_version mismatch')),
    'dictionary mismatch error',
);

$nullName = $orch->planUpdate(
    'customer',
    PatchValidator::PATH_CUSTOMER_CATALOG_PATCH,
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

$phoneSame = $orch->planUpdate(
    'customer',
    PatchValidator::PATH_CUSTOMER_CATALOG_PATCH,
    $entityId,
    'patch',
    [
        'operation_id' => 'op-phone-same',
        'base_row_version' => 5,
        'changed_fields' => ['phone' => '0500000000'],
        'dictionary_version' => '1.0.0',
    ],
    ['changed_fields' => ['phone' => '0500000000']],
    $server,
    5,
);
assertSame(CatalogVersionGate::DECISION_NO_OP, $phoneSame['decision'], 'unchanged phone => no_op');

$phoneClear = $orch->planUpdate(
    'customer',
    PatchValidator::PATH_CUSTOMER_CATALOG_PATCH,
    $entityId,
    'patch',
    [
        'operation_id' => 'op-phone-clear',
        'base_row_version' => 5,
        'changed_fields' => ['phone' => ''],
        'dictionary_version' => '1.0.0',
    ],
    ['changed_fields' => ['phone' => '']],
    $server,
    6,
);
assertSame(CatalogVersionGate::DECISION_APPLY, $phoneClear['decision'], 'phone blank => null change');
assertSame(null, $phoneClear['normalized_changed_fields']['phone'], 'phone normalized null');

$decDiff = $orch->planUpdate(
    'customer',
    PatchValidator::PATH_CUSTOMER_CATALOG_PATCH,
    $entityId,
    'patch',
    [
        'operation_id' => 'op-credit',
        'base_row_version' => 5,
        'changed_fields' => ['credit_limit' => '1500.0000'],
        'dictionary_version' => '1.0.0',
    ],
    ['changed_fields' => ['credit_limit' => '1500.0000']],
    $server,
    6,
);
assertSame(CatalogVersionGate::DECISION_APPLY, $decDiff['decision'], 'credit_limit change => apply');
assertSame('1500.0000', $decDiff['normalized_changed_fields']['credit_limit'], 'credit_limit normalized');

$invalidChanged = $orch->planUpdate(
    'customer',
    PatchValidator::PATH_CUSTOMER_CATALOG_PATCH,
    $entityId,
    'patch',
    [
        'operation_id' => 'op-bad-cf',
        'base_row_version' => 5,
        'dictionary_version' => '1.0.0',
    ],
    ['phone' => '055'],
    $server,
    6,
);
assertSame('validation_error', $invalidChanged['decision'], 'missing changed_fields on native patch');

// ---------------------------------------------------------------------------
// 6) Push validators BC + patch
// ---------------------------------------------------------------------------
echo "\n-- CustomersPushValidator / SuppliersPushValidator --\n";
$vLegacy = new CustomersPushValidator([
    'company_id' => '550e8400-e29b-41d4-a716-446655440000',
    'branch_id' => '660e8400-e29b-41d4-a716-446655440001',
    'device_id' => '770e8400-e29b-41d4-a716-446655440002',
    'batch_id' => '880e8400-e29b-41d4-a716-446655440003',
    'events' => [[
        'outbox_id' => 'o1',
        'entity_type' => 'customer',
        'entity_id' => $entityId,
        'operation' => 'update',
        'payload_json' => ['name' => 'Acme Customer', 'phone' => '1'],
        'idempotency_key' => 'k1',
        'client_row_version' => 2,
    ]],
]);
assertFalse($vLegacy->failed(), 'legacy update still validates (migration BC)');

$vPatch = new CustomersPushValidator([
    'company_id' => '550e8400-e29b-41d4-a716-446655440000',
    'branch_id' => '660e8400-e29b-41d4-a716-446655440001',
    'device_id' => '770e8400-e29b-41d4-a716-446655440002',
    'batch_id' => '880e8400-e29b-41d4-a716-446655440003',
    'events' => [[
        'outbox_id' => 'o2',
        'entity_type' => 'customer',
        'entity_id' => $entityId,
        'operation' => 'patch',
        'base_row_version' => 5,
        'changed_fields' => ['phone'],
        'payload_json' => ['phone' => '055'],
        'idempotency_key' => 'k2',
        'client_row_version' => 6,
    ]],
]);
assertFalse($vPatch->failed(), 'native patch validates without name');

$vPatchBad = new CustomersPushValidator([
    'company_id' => '550e8400-e29b-41d4-a716-446655440000',
    'branch_id' => '660e8400-e29b-41d4-a716-446655440001',
    'device_id' => '770e8400-e29b-41d4-a716-446655440002',
    'batch_id' => '880e8400-e29b-41d4-a716-446655440003',
    'events' => [[
        'outbox_id' => 'o3',
        'entity_type' => 'customer',
        'entity_id' => $entityId,
        'operation' => 'patch',
        'payload_json' => ['phone' => '055'],
        'idempotency_key' => 'k3',
    ]],
]);
assertTrue($vPatchBad->failed(), 'patch without base/changed_fields fails validation');

$vSupplierLegacy = new SuppliersPushValidator([
    'company_id' => '550e8400-e29b-41d4-a716-446655440000',
    'branch_id' => '660e8400-e29b-41d4-a716-446655440001',
    'device_id' => '770e8400-e29b-41d4-a716-446655440002',
    'batch_id' => '880e8400-e29b-41d4-a716-446655440003',
    'events' => [[
        'outbox_id' => 'o4',
        'entity_type' => 'supplier',
        'entity_id' => $supplierId,
        'operation' => 'update',
        'payload_json' => ['name' => 'Acme Supplier'],
        'idempotency_key' => 'k4',
        'client_row_version' => 1,
    ]],
]);
assertFalse($vSupplierLegacy->failed(), 'supplier legacy update validates');

$vSupplierPatch = new SuppliersPushValidator([
    'company_id' => '550e8400-e29b-41d4-a716-446655440000',
    'branch_id' => '660e8400-e29b-41d4-a716-446655440001',
    'device_id' => '770e8400-e29b-41d4-a716-446655440002',
    'batch_id' => '880e8400-e29b-41d4-a716-446655440003',
    'events' => [[
        'outbox_id' => 'o5',
        'entity_type' => 'supplier',
        'entity_id' => $supplierId,
        'operation' => 'patch',
        'base_row_version' => 3,
        'changed_fields' => ['phone'],
        'payload_json' => ['phone' => '011'],
        'idempotency_key' => 'k5',
        'client_row_version' => 4,
    ]],
]);
assertFalse($vSupplierPatch->failed(), 'supplier native patch validates');

// ---------------------------------------------------------------------------
// 7) Short supplier section — native patch + adapter
// ---------------------------------------------------------------------------
echo "\n-- Supplier short section --\n";
$supplierServer = [
    'name' => 'Acme Supplier',
    'phone' => '0110000000',
    'address' => null,
    'notes' => null,
    'partner_number' => 'S1',
    'credit_limit' => '0.0000',
    'overdue_alert_days' => null,
    'supplier_group_id' => null,
    'row_version' => 3,
];
$supPlan = $orch->planUpdate(
    'supplier',
    PatchValidator::PATH_SUPPLIER_CATALOG_PATCH,
    $supplierId,
    'patch',
    [
        'operation_id' => 'op-sup-phone',
        'base_row_version' => 3,
        'changed_fields' => ['phone'],
        'dictionary_version' => '1.0.0',
    ],
    ['phone' => '0112223333'],
    $supplierServer,
    4,
);
assertSame(CatalogVersionGate::DECISION_APPLY, $supPlan['decision'], 'supplier native patch apply');
assertSame(['phone' => '0112223333'], $supPlan['normalized_changed_fields'], 'supplier only phone');
assertSame('Acme Supplier', applyPatchInMemory(
    $supplierServer,
    $supPlan['normalized_changed_fields'],
    $supPlan['new_row_version'],
)['name'], 'supplier HVLU name preserved');

$supAdapted = $orch->planUpdate(
    'supplier',
    PatchValidator::PATH_SUPPLIER_CATALOG_PATCH,
    $supplierId,
    'update',
    ['operation_id' => 'op-sup-legacy'],
    [
        'name' => 'Acme Supplier',
        'phone' => '0112223333',
        'partner_number' => 'S1',
        'credit_limit' => 0,
    ],
    $supplierServer,
    4,
);
assertSame('full_to_patch_adapter', $supAdapted['source'], 'supplier adapter source');
assertSame(['phone' => '0112223333'], $supAdapted['normalized_changed_fields'], 'supplier adapter phone-only');

// ---------------------------------------------------------------------------
// 8) Integration: detect → build → validate → gate → apply
// ---------------------------------------------------------------------------
echo "\n-- Integration pipeline --\n";
$adapter = $orch->adapter();
$built = $adapter->adapt('customer', $entityId, $server, [
    'name' => 'Acme Customer',
    'phone' => '0554445566',
    'address' => 'Riyadh',
    'partner_number' => '1',
    'credit_limit' => 1000,
    'overdue_alert_days' => 30,
], 'op-int-1');
$vr = $orch->validator()->validate($built, PatchValidator::PATH_CUSTOMER_CATALOG_PATCH);
assertSame(PatchValidator::RESULT_VALID, $vr['status'], 'integration validator');
$decision = CatalogVersionGate::decidePatch(5, (int) $built['base_row_version'], $built['changed_fields'] === []);
assertSame(CatalogVersionGate::DECISION_APPLY, $decision, 'integration gate');
$applied = applyPatchInMemory($server, $vr['normalized_changed_fields'] ?? [], 6);
assertSame('0554445566', $applied['phone'], 'integration applied phone');
assertSame('Acme Customer', $applied['name'], 'integration preserved name');
assertSame(6, $applied['row_version'], 'integration version');

$mapPlan = $orch->planUpdate(
    'customer',
    PatchValidator::PATH_CUSTOMER_CATALOG_PATCH,
    $entityId,
    'update',
    [
        'contract_version' => 2,
        'operation_id' => 'op-map',
        'base_row_version' => 5,
        'changed_fields' => ['name' => 'Beta Customer'],
        'dictionary_version' => '1.0.0',
    ],
    [],
    $server,
    6,
);
assertSame('native_patch', $mapPlan['source'], 'contract_version 2 => native');
assertSame(['name' => 'Beta Customer'], $mapPlan['normalized_changed_fields'], 'map-form name patch');

echo "\n=== Results: {$passed} passed, {$failed} failed ===\n";
exit($failed > 0 ? 1 : 0);
