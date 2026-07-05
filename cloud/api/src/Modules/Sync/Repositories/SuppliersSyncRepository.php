<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

use MizaCloud\Modules\Sync\Support\PartnerEntityLww;

final class SuppliersSyncRepository extends SyncRepositorySupport
{
    use PartnerEntityLww;

    public const ENTITY_TYPE = 'supplier';

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function applySupplierLww(
        string $companyId,
        string $branchId,
        string $entityId,
        string $operation,
        array $payload,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        return $this->applyPartnerLww(
            'suppliers',
            'supplier_number',
            $companyId,
            $branchId,
            $entityId,
            $operation,
            $payload,
            $clientRowVersion,
            $originDeviceId,
        );
    }
}
