<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Services;

use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Modules\Devices\Support\BearerToken;
use MizaCloud\Modules\Sync\Repositories\ExpensesSyncRepository;
use MizaCloud\Modules\Sync\Validators\CatalogPullValidator;
use MizaCloud\Modules\Sync\Validators\ExpensesPushValidator;

final class ExpensesSyncService extends AbstractCatalogSyncService
{
    private const ENTITY_SCOPE = 'expenses';

    public function __construct(
        private readonly ExpensesSyncRepository $repository,
        BearerToken $bearer,
        Logger $logger,
    ) {
        parent::__construct($bearer, $logger);
    }

    /** @param array<string, mixed> $payload @return array{data: array<string, mixed>, status: int} */
    public function push(array $payload, Request $request): array
    {
        $claims = $this->bearer->authenticate($request, ['sync:push']);
        $authUserId = (string) ($claims['sub'] ?? $claims['user_id'] ?? '');

        return $this->pushEntities(
            $payload,
            $request,
            new ExpensesPushValidator($payload),
            self::ENTITY_SCOPE,
            ExpensesSyncRepository::ENTITY_TYPE,
            function (
                string $companyId,
                string $branchId,
                string $entityId,
                string $operation,
                array $payloadJson,
                int $clientRowVersion,
                ?string $originDeviceId,
            ) use ($authUserId) {
                if ($authUserId !== '') {
                    $payloadJson['created_by_user_id'] = $authUserId;
                }

                return $this->repository->applyExpenseLww(
                    $companyId,
                    $branchId,
                    $entityId,
                    $operation,
                    $payloadJson,
                    $clientRowVersion,
                    $originDeviceId,
                );
            },
            preAuthenticatedClaims: $claims,
        );
    }

    /** @return array{data: array<string, mixed>, meta: array<string, mixed>} */
    public function pull(Request $request): array
    {
        return $this->pullEntities(
            $request,
            new CatalogPullValidator($request->query),
            self::ENTITY_SCOPE,
            ExpensesSyncRepository::ENTITY_TYPE,
            fn (...$args) => $this->repository->fetchChangelog(...$args),
        );
    }

    protected function repository(): ExpensesSyncRepository
    {
        return $this->repository;
    }
}
