<?php

declare(strict_types=1);

/**
 * Smoke test for SyncPushBatchExecutor::finalizeOrThrowPartial
 * (no DB — validates partial_reject contract shape).
 *
 * Run: php cloud/api/src/Modules/Sync/test_partial_reject_unit.php
 */

require_once dirname(__DIR__, 3) . '/vendor/autoload.php';

// Minimal autoload when composer vendor is absent in this tree.
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

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Modules\Sync\Support\SyncPushBatchExecutor;

function assertTrue(bool $cond, string $msg): void
{
    if (!$cond) {
        fwrite(STDERR, "FAIL: {$msg}\n");
        exit(1);
    }
    echo "OK: {$msg}\n";
}

// 1) Clean success
$ok = SyncPushBatchExecutor::finalizeOrThrowPartial('batch-1', [
    'accepted' => 2,
    'duplicates' => 0,
    'sequences' => [10, 11],
    'rejected_events' => [],
]);
assertTrue(($ok['status'] ?? 0) === 202, 'full accept returns 202');
assertTrue(($ok['data']['rejected'] ?? -1) === 0, 'rejected is 0 on success');

// 2) All duplicates
$dup = SyncPushBatchExecutor::finalizeOrThrowPartial('batch-2', [
    'accepted' => 0,
    'duplicates' => 3,
    'sequences' => [],
    'rejected_events' => [],
]);
assertTrue(($dup['status'] ?? 0) === 200, 'all duplicates returns 200');
assertTrue(($dup['data']['status'] ?? '') === 'duplicate', 'status=duplicate');

// 3) Partial reject throws with contract data
try {
    SyncPushBatchExecutor::finalizeOrThrowPartial('batch-3', [
        'accepted' => 1,
        'duplicates' => 0,
        'sequences' => [42],
        'rejected_events' => [
            [
                'outbox_id' => 'ob-2',
                'error_code' => 'insufficient_stock',
                'message' => 'stock would go negative',
            ],
        ],
    ]);
    assertTrue(false, 'partial reject should throw');
} catch (HttpException $e) {
    assertTrue($e->errorCode === 'partial_reject', 'error code partial_reject');
    assertTrue($e->statusCode === 422, 'HTTP 422');
    $data = is_array($e->data) ? $e->data : [];
    assertTrue(($data['accepted'] ?? null) === 1, 'data.accepted=1');
    assertTrue(($data['rejected'] ?? null) === 1, 'data.rejected=1');
    assertTrue(($data['rejected_events'][0]['outbox_id'] ?? '') === 'ob-2', 'rejected outbox_id');
    assertTrue(($data['rejected_events'][0]['error_code'] ?? '') === 'insufficient_stock', 'error_code');
    assertTrue(($data['batch_id'] ?? '') === 'batch-3', 'batch_id preserved');
}

echo "\nAll partial_reject unit checks passed.\n";
