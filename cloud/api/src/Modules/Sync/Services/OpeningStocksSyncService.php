<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Services;

use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Modules\Devices\Support\BearerToken;
use MizaCloud\Modules\Sync\Repositories\OpeningStocksSyncRepository;
use MizaCloud\Modules\Sync\Validators\CatalogPullValidator;
use MizaCloud\Modules\Sync\Validators\OpeningStocksPushValidator;

final class OpeningStocksSyncService extends AbstractTransactionSyncService
{
    private const ENTITY_SCOPE = 'opening_stocks';

    public function __construct(
        private readonly OpeningStocksSyncRepository $repository,
        BearerToken $bearer,
        Logger $logger,
    ) {
        parent::__construct($bearer, $logger);
    }

    /** @param array<string, mixed> $payload @return array{data: array<string, mixed>, status: int} */
    public function push(array $payload, Request $request): array
    {
        return $this->pushTransactions(
            $payload,
            $request,
            new OpeningStocksPushValidator($payload),
            self::ENTITY_SCOPE,
            OpeningStocksSyncRepository::ENTITY_TYPE,
            fn (...$args) => $this->repository->applyOpeningStockDraftLww(...$args),
        );
    }

    /** @return array{data: array<string, mixed>, meta: array<string, mixed>} */
    public function pull(Request $request): array
    {
        return $this->pullTransactions(
            $request,
            new CatalogPullValidator($request->query),
            self::ENTITY_SCOPE,
            OpeningStocksSyncRepository::ENTITY_TYPE,
            fn (...$args) => $this->repository->fetchChangelog(...$args),
        );
    }

    protected function repository(): OpeningStocksSyncRepository
    {
        return $this->repository;
    }
}
