<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Services;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Modules\Devices\Support\BearerToken;
use MizaCloud\Modules\Sync\Repositories\ProductCategoriesSyncRepository;
use MizaCloud\Modules\Sync\Validators\CatalogPullValidator;
use MizaCloud\Modules\Sync\Validators\ProductCategoriesPushValidator;
use Throwable;

final class ProductCategoriesSyncService extends AbstractCatalogSyncService
{
    private const ENTITY_SCOPE = 'product_categories';

    public function __construct(
        private readonly ProductCategoriesSyncRepository $repository,
        BearerToken $bearer,
        Logger $logger,
    ) {
        parent::__construct($bearer, $logger);
    }

    /** @param array<string, mixed> $payload @return array{data: array<string, mixed>, status: int} */
    public function push(array $payload, Request $request): array
    {
        return $this->pushEntities(
            $payload,
            $request,
            new ProductCategoriesPushValidator($payload),
            self::ENTITY_SCOPE,
            ProductCategoriesSyncRepository::ENTITY_TYPE,
            fn (...$args) => $this->repository->applyCategoryLww(...$args),
        );
    }

    /** @return array{data: array<string, mixed>, meta: array<string, mixed>} */
    public function pull(Request $request): array
    {
        return $this->pullEntities(
            $request,
            new CatalogPullValidator($request->query),
            self::ENTITY_SCOPE,
            ProductCategoriesSyncRepository::ENTITY_TYPE,
            fn (...$args) => $this->repository->fetchChangelog(...$args),
        );
    }

    protected function repository(): ProductCategoriesSyncRepository
    {
        return $this->repository;
    }
}
