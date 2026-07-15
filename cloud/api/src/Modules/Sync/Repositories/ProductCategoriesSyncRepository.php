<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

use MizaCloud\Modules\Sync\Contract\PatchValidator;
use MizaCloud\Modules\Sync\Support\CatalogPatchOrchestrator;
use MizaCloud\Modules\Sync\Support\NamedEntityLww;

final class ProductCategoriesSyncRepository extends SyncRepositorySupport
{
    use NamedEntityLww;

    public const ENTITY_TYPE = 'product_category';

    public function __construct(
        \MizaCloud\Core\Database\Connection $db,
        private readonly CatalogPatchOrchestrator $patchOrchestrator,
    ) {
        parent::__construct($db);
    }

    protected function namedPatchOrchestrator(): CatalogPatchOrchestrator
    {
        return $this->patchOrchestrator;
    }

    protected function namedEntityType(): string
    {
        return self::ENTITY_TYPE;
    }

    protected function namedEntityPath(): string
    {
        return PatchValidator::PATH_PRODUCT_CATEGORY_CATALOG_PATCH;
    }

    protected function namedTable(): string
    {
        return 'product_categories';
    }

    /** @return list<string> */
    protected function namedPatchableColumns(): array
    {
        return ['name', 'sort_order'];
    }

    /**
     * @param array<string, mixed> $payload
     * @param array<string, mixed> $event
     * @return array<string, mixed>
     */
    public function applyCategoryLww(
        string $companyId,
        string $branchId,
        string $entityId,
        string $operation,
        array $payload,
        int $clientRowVersion,
        ?string $originDeviceId,
        array $event = [],
    ): array {
        return $this->applyNamedEntityLww(
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
