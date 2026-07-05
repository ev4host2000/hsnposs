<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

use MizaCloud\Modules\Sync\Support\SalesInvoiceDraftLww;

final class SalesInvoicesSyncRepository extends SyncRepositorySupport
{
    use SalesInvoiceDraftLww;

    public const ENTITY_TYPE = 'sales_invoice';

    /**
     * @param array<string, mixed> $payloadJson
     * @return array<string, mixed>
     */
    public function applySalesInvoiceDraftLww(
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
