<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

use MizaCloud\Modules\Sync\Support\SalesReturnDraftLww;

final class SalesReturnsSyncRepository extends SyncRepositorySupport
{
    use SalesReturnDraftLww;

    public const ENTITY_TYPE = 'sales_return';

    /**
     * @param array<string, mixed> $payloadJson
     * @return array<string, mixed>
     */
    public function applySalesReturnDraftLww(
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
