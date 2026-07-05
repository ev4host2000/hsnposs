<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

use MizaCloud\Modules\Sync\Support\PurchaseInvoiceDraftLww;

final class PurchaseInvoicesSyncRepository extends SyncRepositorySupport
{
    use PurchaseInvoiceDraftLww;

    public const ENTITY_TYPE = 'purchase_invoice';

    /**
     * @param array<string, mixed> $payloadJson
     * @return array<string, mixed>
     */
    public function applyPurchaseInvoiceDraftLww(
        string $companyId,
        string $branchId,
        string $entityId,
        string $operation,
        array $payloadJson,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        return $this->applyDraftLww(
            $companyId,
            $branchId,
            $entityId,
            $operation,
            $payloadJson,
            $clientRowVersion,
            $originDeviceId,
        );
    }
}
