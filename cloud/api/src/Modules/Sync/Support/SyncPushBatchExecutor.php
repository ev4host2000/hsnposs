<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Support;

use MizaCloud\Core\Database\Connection;
use MizaCloud\Core\Exceptions\HttpException;
use Throwable;

/**
 * Applies sync push events with per-event savepoints so one failure
 * does not roll back the whole batch (contract: partial_reject 422).
 */
final class SyncPushBatchExecutor
{
    /**
     * @param list<array<string, mixed>> $events
     * @param callable(array<string, mixed>): array{kind: 'accepted'|'duplicate', sequence?: int} $applyEvent
     * @return array{
     *   accepted: int,
     *   duplicates: int,
     *   sequences: list<int>,
     *   rejected_events: list<array{outbox_id: string, error_code: string, message: string}>
     * }
     */
    public static function run(Connection $db, array $events, callable $applyEvent): array
    {
        $accepted = 0;
        $duplicates = 0;
        $sequences = [];
        $rejectedEvents = [];

        foreach ($events as $index => $event) {
            $savepoint = 'sync_push_' . $index;
            $db->createSavepoint($savepoint);
            try {
                $result = $applyEvent($event);
                $db->releaseSavepoint($savepoint);

                $kind = (string) ($result['kind'] ?? '');
                if ($kind === 'duplicate') {
                    $duplicates++;
                    continue;
                }

                $accepted++;
                if (isset($result['sequence'])) {
                    $sequences[] = (int) $result['sequence'];
                }
            } catch (HttpException $e) {
                $db->rollbackToSavepoint($savepoint);
                $rejectedEvents[] = self::rejectedEventFrom($event, $e->errorCode, $e->getMessage());
            } catch (Throwable $e) {
                $db->rollbackToSavepoint($savepoint);
                $mapped = self::mapThrowable($e);
                $rejectedEvents[] = self::rejectedEventFrom(
                    $event,
                    $mapped['code'],
                    $mapped['message'],
                );
            }
        }

        return [
            'accepted' => $accepted,
            'duplicates' => $duplicates,
            'sequences' => $sequences,
            'rejected_events' => $rejectedEvents,
        ];
    }

    /**
     * @param array{
     *   accepted: int,
     *   duplicates: int,
     *   sequences: list<int>,
     *   rejected_events: list<array{outbox_id: string, error_code: string, message: string}>
     * } $outcome
     * @return array{data: array<string, mixed>, status: int}
     */
    public static function finalizeOrThrowPartial(
        string $batchId,
        array $outcome,
    ): array {
        $accepted = $outcome['accepted'];
        $duplicates = $outcome['duplicates'];
        $rejectedEvents = $outcome['rejected_events'];
        $rejected = count($rejectedEvents);
        $sequences = $outcome['sequences'];

        if ($rejected > 0) {
            throw new HttpException(
                'partial_reject',
                'Some events rejected',
                422,
                [],
                [
                    'batch_id' => $batchId,
                    'status' => 'partial',
                    'accepted' => $accepted,
                    'duplicates' => $duplicates,
                    'rejected' => $rejected,
                    'rejected_events' => $rejectedEvents,
                    'queued_at' => gmdate('Y-m-d\TH:i:s.v\Z'),
                    'changelog_sequences' => $sequences,
                ],
            );
        }

        $statusLabel = $accepted === 0 && $duplicates > 0 ? 'duplicate' : 'accepted';
        $httpStatus = $statusLabel === 'duplicate' ? 200 : 202;

        return [
            'status' => $httpStatus,
            'data' => [
                'batch_id' => $batchId,
                'status' => $statusLabel,
                'accepted' => $accepted,
                'duplicates' => $duplicates,
                'rejected' => 0,
                'queued_at' => gmdate('Y-m-d\TH:i:s.v\Z'),
                'changelog_sequences' => $sequences,
            ],
        ];
    }

    /**
     * @param array<string, mixed> $event
     * @return array{outbox_id: string, error_code: string, message: string}
     */
    private static function rejectedEventFrom(array $event, string $errorCode, string $message): array
    {
        return [
            'outbox_id' => (string) ($event['outbox_id'] ?? ''),
            'error_code' => $errorCode !== '' ? $errorCode : 'apply_failed',
            'message' => $message,
        ];
    }

    /**
     * Maps PDO/FK failures to actionable sync error codes for client repair.
     *
     * @return array{code: string, message: string}
     */
    private static function mapThrowable(Throwable $e): array
    {
        $message = $e->getMessage() !== '' ? $e->getMessage() : 'Event apply failed';
        $lower = strtolower($message);

        if (
            str_contains($lower, 'fk_sales_returns_original_invoice')
            || str_contains($lower, 'fk_purchase_returns_original_invoice')
            || str_contains($lower, 'original_invoice_id')
        ) {
            return ['code' => 'invoice_not_found', 'message' => $message];
        }
        if (
            str_contains($lower, 'fk_sales_invoice_items_product')
            || str_contains($lower, 'fk_purchase_invoice_items_product')
            || str_contains($lower, 'fk_sales_return_items_product')
            || str_contains($lower, 'fk_purchase_return_items_product')
            || str_contains($lower, 'fk_stock_movements_product')
            || (str_contains($lower, 'product_id') && str_contains($lower, 'foreign key'))
        ) {
            return ['code' => 'product_not_found', 'message' => $message];
        }
        if (
            str_contains($lower, 'fk_sales_invoices_customer')
            || str_contains($lower, 'fk_sales_returns_customer')
            || str_contains($lower, 'fk_purchase_invoices_supplier')
            || str_contains($lower, 'fk_purchase_returns_supplier')
            || (str_contains($lower, 'customer_id') && str_contains($lower, 'foreign key'))
            || (str_contains($lower, 'supplier_id') && str_contains($lower, 'foreign key'))
            || (str_contains($lower, 'partner_id') && str_contains($lower, 'foreign key'))
        ) {
            return ['code' => 'partner_not_found', 'message' => $message];
        }

        return ['code' => 'apply_failed', 'message' => $message];
    }
}
