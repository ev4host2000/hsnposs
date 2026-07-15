<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Services;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Modules\Devices\Support\BearerToken;
use MizaCloud\Modules\Sync\Repositories\ProductsSyncRepository;
use MizaCloud\Modules\Sync\Support\SyncPushBatchExecutor;
use MizaCloud\Modules\Sync\Validators\ProductsPullValidator;
use MizaCloud\Modules\Sync\Validators\ProductsPushValidator;
use Throwable;

final class ProductsSyncService
{
    private const ENTITY_SCOPE = 'products';

    public function __construct(
        private readonly ProductsSyncRepository $repository,
        private readonly BearerToken $bearer,
        private readonly Logger $logger,
    ) {}

    /**
     * @param array<string, mixed> $payload
     * @return array{data: array<string, mixed>, status: int}
     */
    public function pushProducts(array $payload, Request $request): array
    {
        $claims = $this->bearer->authenticate($request, ['sync:push']);
        $this->assertDeviceContext($request, $claims, $payload);

        $validator = new ProductsPushValidator($payload);
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
            throw new HttpException('forbidden', 'Company mismatch', 403);
        }

        $accepted = 0;
        $duplicates = 0;
        $sequences = [];

        $this->repository->beginTransaction();
        try {
            $outcome = SyncPushBatchExecutor::run(
                $this->repository->database(),
                $events,
                function (array $event) use (
                    $companyId,
                    $branchId,
                    $deviceId,
                    $batchId,
                ): array {
                    $idempotencyKey = (string) $event['idempotency_key'];
                    if ($this->repository->findQueueByIdempotency($deviceId, $idempotencyKey) !== null) {
                        return ['kind' => 'duplicate'];
                    }

                    $entityId = (string) $event['entity_id'];
                    $operation = (string) $event['operation'];
                    $clientRowVersion = (int) ($event['client_row_version'] ?? 1);
                    $payloadJson = is_array($event['payload_json'] ?? null)
                        ? $event['payload_json']
                        : [];
                    $occurredAt = isset($event['occurred_at']) ? (string) $event['occurred_at'] : null;

                    $applied = $this->repository->applyProductLww(
                        $companyId,
                        $branchId,
                        $entityId,
                        $operation,
                        $payloadJson,
                        $clientRowVersion,
                        $deviceId,
                        $event,
                    );

                    // Safe Equality no-op: accept without mutating changelog / queue / sequence.
                    if (($applied['no_op'] ?? false) === true) {
                        return ['kind' => 'accepted'];
                    }

                    $sequence = $this->repository->nextSyncSequence($companyId);
                    $changelogPayload = $operation === 'delete'
                        ? ['id' => $entityId, 'deleted' => true, 'row_version' => $applied['row_version']]
                        : $applied;

                    $this->repository->insertChangelog(
                        $companyId,
                        $branchId,
                        $sequence,
                        $entityId,
                        $operation,
                        $changelogPayload,
                        (int) $applied['row_version'],
                        $deviceId,
                        $occurredAt,
                    );

                    $this->repository->insertSyncQueue(
                        $companyId,
                        $branchId,
                        $deviceId,
                        $batchId,
                        $entityId,
                        $operation,
                        $changelogPayload,
                        $clientRowVersion,
                        $idempotencyKey,
                    );

                    return ['kind' => 'accepted', 'sequence' => $sequence];
                },
            );

            if ($outcome['accepted'] > 0) {
                $this->repository->bumpCloudVersion($companyId, $branchId, self::ENTITY_SCOPE);
            }

            $this->repository->commit();
        } catch (Throwable $e) {
            $this->repository->rollBack();
            throw $e;
        }

        $this->logger->info('sync.push.products', [
            'batch_id' => $batchId,
            'device_id' => $deviceId,
            'accepted' => $outcome['accepted'],
            'duplicates' => $outcome['duplicates'],
            'rejected' => count($outcome['rejected_events']),
        ]);

        return SyncPushBatchExecutor::finalizeOrThrowPartial($batchId, $outcome);
    }

    /** @return array{data: array<string, mixed>, meta: array<string, mixed>} */
    public function pullProducts(Request $request): array
    {
        $claims = $this->bearer->authenticate($request, ['sync:pull']);
        $query = $request->query;

        $validator = new ProductsPullValidator($query);
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
            throw new HttpException('forbidden', 'Company mismatch', 403);
        }

        $rows = $this->repository->fetchProductChangelog(
            $companyId,
            $branchId,
            $sinceSequence,
            $limit + 1,
        );

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
                'entity_type' => 'product',
                'entity_id' => (string) $row['entity_id'],
                'operation' => (string) $row['operation'],
                'payload_json' => $payload,
                'row_version' => (int) $row['row_version'],
                'origin_device_id' => $row['origin_device_id'],
                'occurred_at' => $this->formatTimestamp((string) $row['occurred_at']),
            ];
        }

        return [
            'data' => [
                'company_id' => $companyId,
                'branch_id' => $branchId ?? '',
                'entity_scope' => self::ENTITY_SCOPE,
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
    private function assertDeviceContext(Request $request, array $claims, array $payload): void
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

    private function formatTimestamp(string $value): string
    {
        $time = strtotime($value);

        return $time === false ? $value : gmdate('Y-m-d\TH:i:s.v\Z', $time);
    }
}
