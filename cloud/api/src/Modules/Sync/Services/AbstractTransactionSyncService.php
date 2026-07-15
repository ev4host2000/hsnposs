<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Services;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Modules\Admin\Services\OpsAuditWriter;
use MizaCloud\Modules\Admin\Support\OpsAuditActions;
use MizaCloud\Modules\Devices\Support\BearerToken;
use MizaCloud\Modules\Sync\Repositories\SyncRepositorySupport;
use MizaCloud\Modules\Sync\Support\SyncPushBatchExecutor;
use MizaCloud\Modules\Sync\Validators\SyncValidator;
use Throwable;

abstract class AbstractTransactionSyncService
{
    public function __construct(
        protected readonly BearerToken $bearer,
        protected readonly Logger $logger,
    ) {}

    abstract protected function repository(): SyncRepositorySupport;

    /**
     * @param array<string, mixed> $payload
     * @return array{data: array<string, mixed>, status: int}
     */
    protected function pushTransactions(
        array $payload,
        Request $request,
        SyncValidator $validator,
        string $entityScope,
        string $entityType,
        callable $applyLww,
    ): array {
        $claims = $this->bearer->authenticate($request, ['sync:push']);
        $this->assertDeviceContext($request, $claims, $payload);

        if ($validator->failed()) {
            throw new HttpException('validation_error', 'Validation failed', 400, [
                'fields' => $validator->messages(),
            ]);
        }

        $companyId = (string) $payload['company_id'];
        $branchId = (string) $payload['branch_id'];
        $deviceId = (string) $payload['device_id'];
        $batchId = (string) $payload['batch_id'];
        /** @var list<array<string, mixed>> $events */
        $events = $payload['events'];

        if (($claims['company_id'] ?? '') !== $companyId) {
            OpsAuditWriter::recordAction(OpsAuditActions::ORG_MISMATCH, 'failure', [
                'organization_id' => $companyId,
                'device_id' => $deviceId,
                'entity' => $entityType,
                'error_code' => 'organization_mismatch',
                'reason' => 'company_id claim mismatch on push',
            ], $request);
            throw new HttpException('forbidden', 'Company mismatch', 403);
        }

        $started = microtime(true);
        OpsAuditWriter::recordAction(OpsAuditActions::PUSH_STARTED, 'success', [
            'organization_id' => $companyId,
            'branch_id' => $branchId,
            'device_id' => $deviceId,
            'entity' => $entityType,
            'transaction_uuid' => $batchId,
        ], $request);

        $repo = $this->repository();
        $repo->beginTransaction();
        try {
            $outcome = SyncPushBatchExecutor::run(
                $repo->database(),
                $events,
                function (array $event) use (
                    $repo,
                    $companyId,
                    $branchId,
                    $deviceId,
                    $batchId,
                    $entityType,
                    $applyLww,
                    $claims,
                ): array {
                    $idempotencyKey = (string) $event['idempotency_key'];
                    if ($repo->findQueueByIdempotency($deviceId, $idempotencyKey) !== null) {
                        return ['kind' => 'duplicate'];
                    }

                    $entityId = (string) $event['entity_id'];
                    $operation = (string) $event['operation'];
                    $clientRowVersion = (int) ($event['client_row_version'] ?? 1);
                    $payloadJson = is_array($event['payload_json'] ?? null)
                        ? $event['payload_json']
                        : [];
                    $occurredAt = isset($event['occurred_at']) ? (string) $event['occurred_at'] : null;

                    // Local POS user IDs are not cloud users — remap to JWT subject.
                    $authUserId = (string) ($claims['sub'] ?? $claims['user_id'] ?? '');
                    if ($authUserId !== '') {
                        $payloadJson = $this->remapCreatedByUserId($payloadJson, $authUserId);
                    }

                    $applied = $applyLww(
                        $companyId,
                        $branchId,
                        $entityId,
                        $operation,
                        $payloadJson,
                        $clientRowVersion,
                        $deviceId,
                    );

                    $storedOperation = $this->normalizeStoredOperation($operation);
                    $changelogPayload = $applied;

                    $sequence = $repo->nextSyncSequence($companyId);
                    $repo->insertChangelog(
                        $companyId,
                        $branchId,
                        $sequence,
                        $entityType,
                        $entityId,
                        $storedOperation,
                        $changelogPayload,
                        (int) ($applied['row_version'] ?? $clientRowVersion),
                        $deviceId,
                        $occurredAt,
                    );

                    $repo->insertSyncQueue(
                        $companyId,
                        $branchId,
                        $deviceId,
                        $batchId,
                        $entityType,
                        $entityId,
                        $storedOperation,
                        $changelogPayload,
                        $clientRowVersion,
                        $idempotencyKey,
                    );

                    return ['kind' => 'accepted', 'sequence' => $sequence];
                },
            );

            if ($outcome['accepted'] > 0) {
                $repo->bumpCloudVersion($companyId, $branchId, $entityScope);
            }

            $repo->commit();
        } catch (Throwable $e) {
            $repo->rollBack();
            OpsAuditWriter::recordAction(OpsAuditActions::SYNC_FAILED, 'failure', [
                'organization_id' => $companyId,
                'branch_id' => $branchId,
                'device_id' => $deviceId,
                'entity' => $entityType,
                'transaction_uuid' => $batchId,
                'error_code' => 'sync_push_failed',
                'error_message' => $e->getMessage(),
                'duration' => round((microtime(true) - $started) * 1000, 2),
            ], $request);
            throw $e;
        }

        $this->logger->info("sync.push.{$entityScope}", [
            'batch_id' => $batchId,
            'device_id' => $deviceId,
            'accepted' => $outcome['accepted'],
            'duplicates' => $outcome['duplicates'],
            'rejected' => count($outcome['rejected_events']),
        ]);

        $rejected = count($outcome['rejected_events']);
        $status = $rejected > 0 && $outcome['accepted'] > 0 ? 'partial' : ($rejected > 0 ? 'failure' : 'success');
        $action = $status === 'partial'
            ? OpsAuditActions::PARTIAL_SYNC
            : ($status === 'failure' ? OpsAuditActions::SYNC_FAILED : OpsAuditActions::PUSH_FINISHED);
        OpsAuditWriter::recordAction($action, $status === 'failure' ? 'failure' : 'success', [
            'organization_id' => $companyId,
            'branch_id' => $branchId,
            'device_id' => $deviceId,
            'entity' => $entityType,
            'transaction_uuid' => $batchId,
            'duration' => round((microtime(true) - $started) * 1000, 2),
            'metadata' => [
                'accepted' => $outcome['accepted'],
                'duplicates' => $outcome['duplicates'],
                'rejected' => $rejected,
            ],
        ], $request);

        return SyncPushBatchExecutor::finalizeOrThrowPartial($batchId, $outcome);
    }

    /**
     * @param callable(string, string, ?string, int, int): list<array<string, mixed>> $fetchChangelog
     * @return array{data: array<string, mixed>, meta: array<string, mixed>}
     */
    protected function pullTransactions(
        Request $request,
        SyncValidator $validator,
        string $entityScope,
        string $entityType,
        callable $fetchChangelog,
    ): array {
        $claims = $this->bearer->authenticate($request, ['sync:pull']);
        $query = $request->query;

        if ($validator->failed()) {
            throw new HttpException('validation_error', 'Validation failed', 400, [
                'fields' => $validator->messages(),
            ]);
        }

        $companyId = (string) $query['company_id'];
        $branchId = isset($query['branch_id']) ? (string) $query['branch_id'] : null;
        $sinceSequence = (int) ($query['since_sequence'] ?? 0);
        $limit = min(max((int) ($query['limit'] ?? 100), 1), 500);

        if (($claims['company_id'] ?? '') !== $companyId) {
            OpsAuditWriter::recordAction(OpsAuditActions::ORG_MISMATCH, 'failure', [
                'organization_id' => $companyId,
                'entity' => $entityType,
                'error_code' => 'organization_mismatch',
                'reason' => 'company_id claim mismatch on pull',
            ], $request);
            throw new HttpException('forbidden', 'Company mismatch', 403);
        }

        $started = microtime(true);
        OpsAuditWriter::recordAction(OpsAuditActions::PULL_STARTED, 'success', [
            'organization_id' => $companyId,
            'branch_id' => $branchId,
            'entity' => $entityType,
        ], $request);

        $rows = $fetchChangelog($entityType, $companyId, $branchId, $sinceSequence, $limit + 1);

        $hasMore = count($rows) > $limit;
        if ($hasMore) {
            $rows = array_slice($rows, 0, $limit);
        }

        $entries = [];
        $lastSequence = $sinceSequence;
        foreach ($rows as $row) {
            $sequence = (int) $row['sequence'];
            $lastSequence = max($lastSequence, $sequence);
            $payload = $row['payload_json'];
            if (is_string($payload)) {
                $payload = json_decode($payload, true);
            }
            if (!is_array($payload)) {
                $payload = [];
            }

            $entries[] = [
                'sequence' => $sequence,
                'entity_type' => $entityType,
                'entity_id' => (string) $row['entity_id'],
                'operation' => $this->normalizePullOperation(
                    (string) $row['operation'],
                    $entityType,
                    $payload,
                ),
                'payload_json' => $payload,
                'row_version' => (int) $row['row_version'],
                'origin_device_id' => $row['origin_device_id'],
                'occurred_at' => $this->formatTimestamp((string) $row['occurred_at']),
            ];
        }

        OpsAuditWriter::recordAction(OpsAuditActions::PULL_FINISHED, 'success', [
            'organization_id' => $companyId,
            'branch_id' => $branchId,
            'entity' => $entityType,
            'duration' => round((microtime(true) - $started) * 1000, 2),
            'metadata' => ['entry_count' => count($entries), 'has_more' => $hasMore],
        ], $request);

        return [
            'data' => [
                'company_id' => $companyId,
                'branch_id' => $branchId ?? '',
                'entity_scope' => $entityScope,
                'entries' => $entries,
            ],
            'meta' => [
                'since_sequence' => $sinceSequence,
                'last_sequence' => $lastSequence,
                'has_more' => $hasMore,
                'next_cursor' => null,
                'entry_count' => count($entries),
            ],
        ];
    }

    /** @param array<string, mixed> $claims @param array<string, mixed> $payload */
    protected function assertDeviceContext(Request $request, array $claims, array $payload): void
    {
        $headerDeviceId = $request->headers['X-Device-ID']
            ?? $request->headers['x-device-id']
            ?? '';
        $claimDeviceId = (string) ($claims['device_id'] ?? $claims['sub'] ?? '');
        $bodyDeviceId = (string) ($payload['device_id'] ?? '');

        if ($headerDeviceId !== '' && $claimDeviceId !== '' && $headerDeviceId !== $claimDeviceId) {
            throw new HttpException('forbidden', 'Device header mismatch', 403);
        }
        if ($bodyDeviceId !== '' && $claimDeviceId !== '' && $bodyDeviceId !== $claimDeviceId) {
            throw new HttpException('forbidden', 'Device body mismatch', 403);
        }

        $headerCompany = $request->headers['X-Company-ID'] ?? $request->headers['x-company-id'] ?? '';
        if ($headerCompany !== '' && $headerCompany !== (string) ($payload['company_id'] ?? '')) {
            throw new HttpException('forbidden', 'Company header mismatch', 403);
        }

        $headerBranch = $request->headers['X-Branch-ID'] ?? $request->headers['x-branch-id'] ?? '';
        if ($headerBranch !== '' && $headerBranch !== (string) ($payload['branch_id'] ?? '')) {
            throw new HttpException('forbidden', 'Branch header mismatch', 403);
        }
    }

    protected function formatTimestamp(string $value): string
    {
        $time = strtotime($value);

        return $time === false ? $value : gmdate('Y-m-d\TH:i:s.v\Z', $time);
    }

    protected function normalizeStoredOperation(string $operation): string
    {
        return match ($operation) {
            // Draft cancel stays as delete in changelog for backward compatibility.
            'cancel' => 'delete',
            // Posted invoice void is stored as `void` (migration 018).
            'void' => 'void',
            default => $operation,
        };
    }

    /** @param array<string, mixed> $payload */
    protected function normalizePullOperation(
        string $storedOperation,
        string $entityType,
        array $payload,
    ): string {
        if ($storedOperation === 'void') {
            return 'void';
        }

        if ($storedOperation !== 'delete') {
            return $storedOperation;
        }

        // Legacy: some voids may have been stored as delete before migration 018.
        $status = '';
        if (isset($payload['aggregate']) && is_array($payload['aggregate'])) {
            $header = $payload['aggregate']['header'] ?? null;
            if (is_array($header)) {
                $status = (string) ($header['status'] ?? '');
            }
        }
        if (in_array($status, ['void', 'voided'], true)) {
            return 'void';
        }

        if ($entityType !== 'sales_invoice' && $entityType !== 'purchase_invoice') {
            if (isset($payload['aggregate']) || ($payload['deleted'] ?? false) === true) {
                return 'cancel';
            }

            return $storedOperation;
        }

        if ($entityType === 'sales_invoice' && (isset($payload['aggregate']) || ($payload['deleted'] ?? false) === true)) {
            return 'cancel';
        }
        if ($entityType === 'purchase_invoice' && (isset($payload['aggregate']) || ($payload['deleted'] ?? false) === true)) {
            return 'cancel';
        }

        return $storedOperation;
    }

    /**
     * @param array<string, mixed> $payloadJson
     * @return array<string, mixed>
     */
    protected function remapCreatedByUserId(array $payloadJson, string $authUserId): array
    {
        if (isset($payloadJson['aggregate']) && is_array($payloadJson['aggregate'])) {
            $aggregate = $payloadJson['aggregate'];
            $header = is_array($aggregate['header'] ?? null)
                ? $aggregate['header']
                : [];
            $header['created_by_user_id'] = $authUserId;
            $aggregate['header'] = $header;

            if (isset($aggregate['metadata']) && is_array($aggregate['metadata'])) {
                $aggregate['metadata']['created_by_user_id'] = $authUserId;
            }

            $payloadJson['aggregate'] = $aggregate;
        }

        $payloadJson['created_by_user_id'] = $authUserId;

        return $payloadJson;
    }
}
