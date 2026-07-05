<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

use MizaCloud\Modules\Sync\Support\PurchaseReturnDraftLww;

final class PurchaseReturnsSyncRepository extends SyncRepositorySupport
{
    use PurchaseReturnDraftLww;

    public const ENTITY_TYPE = 'purchase_return';

    /**
     * @param array<string, mixed> $payloadJson
     * @return array<string, mixed>
     */
    public function applyPurchaseReturnDraftLww(
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
