<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

use MizaCloud\Modules\Sync\Support\PartnerEntityLww;

final class CustomersSyncRepository extends SyncRepositorySupport
{
    use PartnerEntityLww;

    public const ENTITY_TYPE = 'customer';

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function applyCustomerLww(
        string $companyId,
        string $branchId,
        string $entityId,
        string $operation,
        array $payload,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        return $this->applyPartnerLww(
            'customers',
            'customer_number',
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
