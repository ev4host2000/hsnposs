<?php

declare(strict_types=1);

/**
 * Unit tests for CatalogVersionGate (pure logic — no DB).
 *
 * Run: php cloud/api/src/Modules/Sync/test_catalog_version_gate_unit.php
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

function decide(
    string $operation,
    ?int $server,
    int $client,
    bool $matches = false,
): string {
    return CatalogVersionGate::decide($operation, $server, $client, $matches);
}

echo "=== CatalogVersionGate unit tests ===\n\n";

// ---------------------------------------------------------------------------
// client < server
// ---------------------------------------------------------------------------
echo "-- client < server --\n";
assertSame(
    CatalogVersionGate::DECISION_CONFLICT,
    decide('update', 5, 2, false),
    'update: client < server => version_conflict',
);
assertSame(
    CatalogVersionGate::DECISION_CONFLICT,
    decide('update', 5, 2, true),
    'update: client < server ignores content match => version_conflict',
);
assertSame(
    CatalogVersionGate::DECISION_CONFLICT,
    decide('create', 5, 1, false),
    'create-on-existing: client < server => version_conflict',
);

// ---------------------------------------------------------------------------
// client > server
// ---------------------------------------------------------------------------
echo "\n-- client > server --\n";
assertSame(
    CatalogVersionGate::DECISION_APPLY,
    decide('update', 5, 6, false),
    'update: client > server => apply',
);
assertSame(
    CatalogVersionGate::DECISION_APPLY,
    decide('update', 5, 6, true),
    'update: client > server applies even if payload equals (version moved forward)',
);

// ---------------------------------------------------------------------------
// client == server + same content
// ---------------------------------------------------------------------------
echo "\n-- client == server + same content --\n";
assertSame(
    CatalogVersionGate::DECISION_NO_OP,
    decide('update', 5, 5, true),
    'update: == + matching payload => no_op',
);
assertSame(
    CatalogVersionGate::DECISION_NO_OP,
    decide('create', 5, 5, true),
    'create-on-existing: == + matching payload => no_op',
);

// ---------------------------------------------------------------------------
// client == server + different content
// ---------------------------------------------------------------------------
echo "\n-- client == server + different content --\n";
assertSame(
    CatalogVersionGate::DECISION_CONFLICT,
    decide('update', 5, 5, false),
    'update: == + different payload => version_conflict',
);
assertSame(
    CatalogVersionGate::DECISION_CONFLICT,
    decide('create', 5, 5, false),
    'create-on-existing: == + different payload => version_conflict',
);

// ---------------------------------------------------------------------------
// Create جديد (no server row)
// ---------------------------------------------------------------------------
echo "\n-- Create جديد --\n";
assertSame(
    CatalogVersionGate::DECISION_APPLY,
    decide('create', null, 1, false),
    'create: no server row => apply',
);
assertSame(
    CatalogVersionGate::DECISION_APPLY,
    decide('create', null, 99, true),
    'create: no server row ignores content flag => apply',
);
assertSame(
    CatalogVersionGate::DECISION_APPLY,
    decide('update', null, 1, false),
    'update with no server row (upsert insert) => apply',
);

// ---------------------------------------------------------------------------
// Delete قديم (client < server)
// ---------------------------------------------------------------------------
echo "\n-- Delete قديم --\n";
assertSame(
    CatalogVersionGate::DECISION_CONFLICT,
    decide('delete', 5, 2, false),
    'delete: client < server (stale) => version_conflict',
);
assertSame(
    CatalogVersionGate::DECISION_CONFLICT,
    decide('delete', 5, 2, true),
    'delete: client < server even if already-deleted flag set => version_conflict',
);

// ---------------------------------------------------------------------------
// Delete جديد (client > server)
// ---------------------------------------------------------------------------
echo "\n-- Delete جديد --\n";
assertSame(
    CatalogVersionGate::DECISION_APPLY,
    decide('delete', 5, 7, false),
    'delete: client > server => apply',
);
assertSame(
    CatalogVersionGate::DECISION_APPLY,
    decide('delete', 5, 7, true),
    'delete: client > server => apply (authoritative newer delete)',
);

// ---------------------------------------------------------------------------
// Delete extras: == active, == already deleted, missing row
// ---------------------------------------------------------------------------
echo "\n-- Delete equality / missing --\n";
assertSame(
    CatalogVersionGate::DECISION_APPLY,
    decide('delete', 5, 5, false),
    'delete: == on active row => apply (authorized delete)',
);
assertSame(
    CatalogVersionGate::DECISION_NO_OP,
    decide('delete', 5, 5, true),
    'delete: == when already deleted => no_op',
);
assertSame(
    CatalogVersionGate::DECISION_NO_OP,
    decide('delete', null, 1, false),
    'delete: no server row => no_op',
);

// ---------------------------------------------------------------------------
// Input validation
// ---------------------------------------------------------------------------
echo "\n-- validation --\n";
try {
    CatalogVersionGate::decide('update', 1, 0, false);
    assertSame(true, false, 'client_row_version < 1 must throw');
} catch (InvalidArgumentException $e) {
    assertSame(true, true, 'client_row_version < 1 throws InvalidArgumentException');
}

try {
    CatalogVersionGate::decide('post', 1, 1, false);
    assertSame(true, false, 'unsupported operation must throw');
} catch (InvalidArgumentException $e) {
    assertSame(true, true, 'unsupported operation throws InvalidArgumentException');
}

// ---------------------------------------------------------------------------
// Update Contract v2 decidePatch
// ---------------------------------------------------------------------------
echo "\n-- decidePatch (Update Contract v2) --\n";
assertSame(
    CatalogVersionGate::DECISION_APPLY,
    CatalogVersionGate::decidePatch(5, 5, false),
    'patch: base==server + changes => apply',
);
assertSame(
    CatalogVersionGate::DECISION_NO_OP,
    CatalogVersionGate::decidePatch(5, 5, true),
    'patch: base==server + no effective change => no_op',
);
assertSame(
    CatalogVersionGate::DECISION_CONFLICT,
    CatalogVersionGate::decidePatch(5, 4, false),
    'patch: base < server => version_conflict',
);
assertSame(
    CatalogVersionGate::DECISION_CONFLICT,
    CatalogVersionGate::decidePatch(5, 6, false),
    'patch: base > server => version_conflict',
);
assertSame(
    CatalogVersionGate::DECISION_CONFLICT,
    CatalogVersionGate::decidePatch(null, 1, false),
    'patch: missing server row => version_conflict',
);
try {
    CatalogVersionGate::decidePatch(5, 0, false);
    assertSame(true, false, 'base_row_version < 1 must throw');
} catch (InvalidArgumentException $e) {
    assertSame(true, true, 'base_row_version < 1 throws');
}

echo "\n=== Summary: passed={$passed} failed={$failed} ===\n";
exit($failed === 0 ? 0 : 1);
