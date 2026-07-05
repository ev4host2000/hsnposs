<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Services;

use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Modules\Devices\Support\BearerToken;
use MizaCloud\Modules\Sync\Repositories\CustomersSyncRepository;
use MizaCloud\Modules\Sync\Validators\CatalogPullValidator;
use MizaCloud\Modules\Sync\Validators\CustomersPushValidator;

final class CustomersSyncService extends AbstractCatalogSyncService
{
    private const ENTITY_SCOPE = 'customers';

    public function __construct(
        private readonly CustomersSyncRepository $repository,
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
            new CustomersPushValidator($payload),
            self::ENTITY_SCOPE,
            CustomersSyncRepository::ENTITY_TYPE,
            fn (...$args) => $this->repository->applyCustomerLww(...$args),
        );
    }

    /** @return array{data: array<string, mixed>, meta: array<string, mixed>} */
    public function pull(Request $request): array
    {
        return $this->pullEntities(
            $request,
            new CatalogPullValidator($request->query),
            self::ENTITY_SCOPE,
            CustomersSyncRepository::ENTITY_TYPE,
            fn (...$args) => $this->repository->fetchChangelog(...$args),
        );
    }

    protected function repository(): CustomersSyncRepository
    {
        return $this->repository;
    }
}
