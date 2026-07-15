<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

use MizaCloud\Modules\Sync\Contract\PatchValidator;
use MizaCloud\Modules\Sync\Support\CatalogPatchOrchestrator;
use MizaCloud\Modules\Sync\Support\PartnerEntityLww;

final class SuppliersSyncRepository extends SyncRepositorySupport
{
    use PartnerEntityLww;

    public const ENTITY_TYPE = 'supplier';

    public function __construct(
        \MizaCloud\Core\Database\Connection $db,
        private readonly CatalogPatchOrchestrator $patchOrchestrator,
    ) {
        parent::__construct($db);
    }

    protected function partnerPatchOrchestrator(): CatalogPatchOrchestrator
    {
        return $this->patchOrchestrator;
    }

    protected function partnerEntityType(): string
    {
        return self::ENTITY_TYPE;
    }

    protected function partnerEntityPath(): string
    {
        return PatchValidator::PATH_SUPPLIER_CATALOG_PATCH;
    }

    protected function partnerTable(): string
    {
        return 'suppliers';
    }

    protected function partnerNumberColumn(): string
    {
        return 'supplier_number';
    }

    /**
     * @param array<string, mixed> $payload
     * @param array<string, mixed> $event
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
        array $event = [],
    ): array {
        return $this->applyPartnerLww(
            $companyId,
            $branchId,
            $entityId,
            $operation,
            $payload,
            $clientRowVersion,
            $originDeviceId,
            $event,
        );
    }
}
