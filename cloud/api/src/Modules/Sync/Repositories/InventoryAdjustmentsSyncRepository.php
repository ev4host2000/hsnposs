<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

use MizaCloud\Modules\Sync\Support\InventoryAdjustmentDraftLww;

final class InventoryAdjustmentsSyncRepository extends SyncRepositorySupport
{
    use InventoryAdjustmentDraftLww;

    public const ENTITY_TYPE = 'inventory_adjustment';

    /**
     * @param array<string, mixed> $payloadJson
     * @return array<string, mixed>
     */
    public function applyInventoryAdjustmentDraftLww(
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
