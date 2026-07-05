<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Catalog\Services;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Request;
use MizaCloud\Modules\Auth\Support\Uuid;
use MizaCloud\Modules\Catalog\Repositories\CatalogRepository;
use MizaCloud\Modules\Devices\Support\BearerToken;
use PDOException;
use RuntimeException;

final class CatalogService
{
    public function __construct(
        private readonly CatalogRepository $repository,
        private readonly BearerToken $bearer,
    ) {}

    /** @return array{data: array<string, mixed>, meta: array<string, mixed>} */
    public function listProductCategories(Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:read']);

        return $this->listResult(
            $this->repository->listProductCategories(
                $tenant['company_id'],
                $tenant['branch_id'],
                $this->listFilters($request),
            ),
            $request,
        );
    }

    /**
     * @param array<string, mixed> $payload
     * @return array{data: array<string, mixed>, status: int}
     */
    public function createProductCategory(array $payload, Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:write']);
        $name = trim((string) ($payload['name'] ?? ''));
        if ($name === '') {
            throw new HttpException('validation_error', 'name is required', 400);
        }

        $id = $this->resolveId($payload);
        $existing = $this->repository->getProductCategory($tenant['company_id'], $id, true);
        if ($existing !== null) {
            if ($existing['deleted_at'] === null && $this->isSameCategory($existing, $payload)) {
                return ['status' => 200, 'data' => $this->createResponse($existing)];
            }
            if ($existing['deleted_at'] === null) {
                throw new HttpException('conflict', 'Category id already exists', 409);
            }
        }

        $this->assertNameAvailable('product_categories', $tenant, $name);

        try {
            $row = $this->repository->createProductCategory(
                $tenant['company_id'],
                $tenant['branch_id'],
                $id,
                $payload,
            );
        } catch (PDOException $e) {
            if ($this->repository->isUniqueViolation($e)) {
                throw new HttpException('name_duplicate', 'Category name already exists', 409);
            }
            throw $e;
        }

        return ['status' => 201, 'data' => $this->createResponse($row)];
    }

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function updateProductCategory(string $id, array $payload, Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:write']);
        $existing = $this->requireEntity($this->repository->getProductCategory($tenant['company_id'], $id));
        $this->assertRowVersion($existing, $payload);

        if (array_key_exists('name', $payload)) {
            $name = trim((string) $payload['name']);
            if ($name === '') {
                throw new HttpException('validation_error', 'name cannot be empty', 400);
            }
            $this->assertNameAvailable('product_categories', $tenant, $name, $id);
        }

        try {
            $row = $this->repository->updateProductCategory($tenant['company_id'], $id, $payload);
        } catch (PDOException $e) {
            if ($this->repository->isUniqueViolation($e)) {
                throw new HttpException('name_duplicate', 'Category name already exists', 409);
            }
            throw $e;
        } catch (RuntimeException) {
            throw new HttpException('not_found', 'Category not found', 404);
        }

        return $this->patchResponse($row);
    }

    /** @return array<string, mixed> */
    public function deleteProductCategory(string $id, Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:write']);
        $this->requireEntity($this->repository->getProductCategory($tenant['company_id'], $id));

        try {
            return $this->repository->softDeleteProductCategory($tenant['company_id'], $id);
        } catch (RuntimeException) {
            throw new HttpException('not_found', 'Category not found', 404);
        }
    }

    /** @return array{data: array<string, mixed>, meta: array<string, mixed>} */
    public function listProductUnits(Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:read']);

        return $this->listResult(
            $this->repository->listProductUnits(
                $tenant['company_id'],
                $tenant['branch_id'],
                $this->listFilters($request),
            ),
            $request,
        );
    }

    /**
     * @param array<string, mixed> $payload
     * @return array{data: array<string, mixed>, status: int}
     */
    public function createProductUnit(array $payload, Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:write']);
        $name = trim((string) ($payload['name'] ?? ''));
        if ($name === '') {
            throw new HttpException('validation_error', 'name is required', 400);
        }

        $id = $this->resolveId($payload);
        $existing = $this->repository->getProductUnit($tenant['company_id'], $id, true);
        if ($existing !== null) {
            if ($existing['deleted_at'] === null && $this->isSameUnit($existing, $payload)) {
                return ['status' => 200, 'data' => $this->createResponse($existing)];
            }
            if ($existing['deleted_at'] === null) {
                throw new HttpException('conflict', 'Unit id already exists', 409);
            }
        }

        $this->assertNameAvailable('product_units', $tenant, $name);

        try {
            $row = $this->repository->createProductUnit(
                $tenant['company_id'],
                $tenant['branch_id'],
                $id,
                $payload,
            );
        } catch (PDOException $e) {
            if ($this->repository->isUniqueViolation($e)) {
                throw new HttpException('name_duplicate', 'Unit name already exists', 409);
            }
            throw $e;
        }

        return ['status' => 201, 'data' => $this->createResponse($row)];
    }

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function updateProductUnit(string $id, array $payload, Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:write']);
        $existing = $this->requireEntity($this->repository->getProductUnit($tenant['company_id'], $id));
        $this->assertRowVersion($existing, $payload);

        if (array_key_exists('name', $payload)) {
            $name = trim((string) $payload['name']);
            if ($name === '') {
                throw new HttpException('validation_error', 'name cannot be empty', 400);
            }
            $this->assertNameAvailable('product_units', $tenant, $name, $id);
        }

        try {
            $row = $this->repository->updateProductUnit($tenant['company_id'], $id, $payload);
        } catch (PDOException $e) {
            if ($this->repository->isUniqueViolation($e)) {
                throw new HttpException('name_duplicate', 'Unit name already exists', 409);
            }
            throw $e;
        } catch (RuntimeException) {
            throw new HttpException('not_found', 'Unit not found', 404);
        }

        return $this->patchResponse($row);
    }

    /** @return array<string, mixed> */
    public function deleteProductUnit(string $id, Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:write']);
        $this->requireEntity($this->repository->getProductUnit($tenant['company_id'], $id));

        try {
            return $this->repository->softDeleteProductUnit($tenant['company_id'], $id);
        } catch (RuntimeException) {
            throw new HttpException('not_found', 'Unit not found', 404);
        }
    }

    /** @return array{data: array<string, mixed>, meta: array<string, mixed>} */
    public function listTaxes(Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:read']);

        return $this->listResult(
            $this->repository->listTaxes(
                $tenant['company_id'],
                $tenant['branch_id'],
                $this->listFilters($request),
            ),
            $request,
        );
    }

    /**
     * @param array<string, mixed> $payload
     * @return array{data: array<string, mixed>, status: int}
     */
    public function createTax(array $payload, Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:write']);
        $name = trim((string) ($payload['name'] ?? ''));
        if ($name === '') {
            throw new HttpException('validation_error', 'name is required', 400);
        }

        $id = $this->resolveId($payload);
        $existing = $this->repository->getTax($tenant['company_id'], $id, true);
        if ($existing !== null) {
            if ($existing['deleted_at'] === null && $this->isSameTax($existing, $payload)) {
                return ['status' => 200, 'data' => $this->createResponse($existing)];
            }
            if ($existing['deleted_at'] === null) {
                throw new HttpException('conflict', 'Tax id already exists', 409);
            }
        }

        $this->assertNameAvailable('taxes', $tenant, $name);

        try {
            $row = $this->repository->createTax(
                $tenant['company_id'],
                $tenant['branch_id'],
                $id,
                $payload,
            );
        } catch (PDOException $e) {
            if ($this->repository->isUniqueViolation($e)) {
                throw new HttpException('name_duplicate', 'Tax name already exists', 409);
            }
            throw $e;
        }

        return ['status' => 201, 'data' => $this->createResponse($row)];
    }

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function updateTax(string $id, array $payload, Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:write']);
        $existing = $this->requireEntity($this->repository->getTax($tenant['company_id'], $id));
        $this->assertRowVersion($existing, $payload);

        if (array_key_exists('name', $payload)) {
            $name = trim((string) $payload['name']);
            if ($name === '') {
                throw new HttpException('validation_error', 'name cannot be empty', 400);
            }
            $this->assertNameAvailable('taxes', $tenant, $name, $id);
        }

        try {
            $row = $this->repository->updateTax($tenant['company_id'], $id, $payload);
        } catch (PDOException $e) {
            if ($this->repository->isUniqueViolation($e)) {
                throw new HttpException('name_duplicate', 'Tax name already exists', 409);
            }
            throw $e;
        } catch (RuntimeException) {
            throw new HttpException('not_found', 'Tax not found', 404);
        }

        return $this->patchResponse($row);
    }

    /** @return array<string, mixed> */
    public function deleteTax(string $id, Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:write']);
        $this->requireEntity($this->repository->getTax($tenant['company_id'], $id));

        try {
            return $this->repository->softDeleteTax($tenant['company_id'], $id);
        } catch (RuntimeException) {
            throw new HttpException('not_found', 'Tax not found', 404);
        }
    }

    /** @return array{data: array<string, mixed>, meta: array<string, mixed>} */
    public function listPriceLists(Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:read']);

        return $this->listResult(
            $this->repository->listPriceLists(
                $tenant['company_id'],
                $tenant['branch_id'],
                $this->listFilters($request),
            ),
            $request,
        );
    }

    /**
     * @param array<string, mixed> $payload
     * @return array{data: array<string, mixed>, status: int}
     */
    public function createPriceList(array $payload, Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:write']);
        $name = trim((string) ($payload['name'] ?? ''));
        if ($name === '') {
            throw new HttpException('validation_error', 'name is required', 400);
        }

        $id = $this->resolveId($payload);
        $existing = $this->repository->getPriceList($tenant['company_id'], $id, true);
        if ($existing !== null) {
            if ($existing['deleted_at'] === null && $this->isSamePriceList($existing, $payload)) {
                return ['status' => 200, 'data' => $this->createResponse($existing)];
            }
            if ($existing['deleted_at'] === null) {
                throw new HttpException('conflict', 'Price list id already exists', 409);
            }
        }

        $this->assertNameAvailable('price_lists', $tenant, $name);

        try {
            $row = $this->repository->createPriceList(
                $tenant['company_id'],
                $tenant['branch_id'],
                $id,
                $payload,
            );
        } catch (PDOException $e) {
            if ($this->repository->isUniqueViolation($e)) {
                throw new HttpException('name_duplicate', 'Price list name already exists', 409);
            }
            throw $e;
        }

        return ['status' => 201, 'data' => $this->createResponse($row)];
    }

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function updatePriceList(string $id, array $payload, Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:write']);
        $existing = $this->requireEntity($this->repository->getPriceList($tenant['company_id'], $id));
        $this->assertRowVersion($existing, $payload);

        if (array_key_exists('name', $payload)) {
            $name = trim((string) $payload['name']);
            if ($name === '') {
                throw new HttpException('validation_error', 'name cannot be empty', 400);
            }
            $this->assertNameAvailable('price_lists', $tenant, $name, $id);
        }

        try {
            $row = $this->repository->updatePriceList(
                $tenant['company_id'],
                $tenant['branch_id'],
                $id,
                $payload,
            );
        } catch (PDOException $e) {
            if ($this->repository->isUniqueViolation($e)) {
                throw new HttpException('name_duplicate', 'Price list name already exists', 409);
            }
            throw $e;
        } catch (RuntimeException) {
            throw new HttpException('not_found', 'Price list not found', 404);
        }

        return $this->patchResponse($row);
    }

    /** @return array<string, mixed> */
    public function deletePriceList(string $id, Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:write']);
        $this->requireEntity($this->repository->getPriceList($tenant['company_id'], $id));

        try {
            return $this->repository->softDeletePriceList($tenant['company_id'], $id);
        } catch (RuntimeException) {
            throw new HttpException('not_found', 'Price list not found', 404);
        }
    }

    /** @return array{company_id: string, branch_id: string} */
    private function tenant(Request $request, array $requiredScopes): array
    {
        $claims = $this->bearer->authenticate($request, $requiredScopes);
        $companyId = (string) ($claims['company_id'] ?? '');
        $branchId = (string) ($claims['branch_id'] ?? '');

        if ($companyId === '' || $branchId === '') {
            throw new HttpException('forbidden', 'Company and branch context required', 403);
        }

        $queryBranch = isset($request->query['branch_id']) ? (string) $request->query['branch_id'] : '';
        if ($queryBranch !== '' && $queryBranch !== $branchId) {
            throw new HttpException('forbidden', 'Branch mismatch', 403);
        }

        return [
            'company_id' => $companyId,
            'branch_id' => $branchId,
        ];
    }

    /** @return array<string, mixed> */
    private function listFilters(Request $request): array
    {
        return [
            'include_deleted' => $request->query['include_deleted'] ?? false,
            'updated_since' => $request->query['updated_since'] ?? null,
            'q' => $request->query['q'] ?? null,
            'page' => $request->query['page'] ?? 1,
            'page_size' => $request->query['page_size'] ?? 50,
        ];
    }

    /**
     * @param array{items: list<array<string, mixed>>, total_count: int} $result
     * @return array{data: array<string, mixed>, meta: array<string, mixed>}
     */
    private function listResult(array $result, Request $request): array
    {
        $page = max(1, (int) ($request->query['page'] ?? 1));
        $pageSize = min(max((int) ($request->query['page_size'] ?? 50), 1), 500);

        return [
            'data' => ['items' => $result['items']],
            'meta' => [
                'page' => $page,
                'page_size' => $pageSize,
                'total_count' => $result['total_count'],
            ],
        ];
    }

    /** @param array<string, mixed> $payload */
    private function resolveId(array $payload): string
    {
        $id = isset($payload['id']) ? (string) $payload['id'] : '';
        if ($id !== '' && !Uuid::isValid($id)) {
            throw new HttpException('validation_error', 'Invalid id', 400);
        }

        return $id !== '' ? $id : Uuid::v4();
    }

    /** @param array<string, mixed>|null $row @return array<string, mixed> */
    private function requireEntity(?array $row): array
    {
        if ($row === null) {
            throw new HttpException('not_found', 'Resource not found', 404);
        }

        return $row;
    }

    /** @param array<string, mixed> $existing @param array<string, mixed> $payload */
    private function assertRowVersion(array $existing, array $payload): void
    {
        if (!array_key_exists('row_version', $payload)) {
            return;
        }

        if ((int) $existing['row_version'] !== (int) $payload['row_version']) {
            throw new HttpException('conflict', 'Row version mismatch', 409);
        }
    }

    /** @param array{company_id: string, branch_id: string} $tenant */
    private function assertNameAvailable(
        string $table,
        array $tenant,
        string $name,
        ?string $excludeId = null,
    ): void {
        if ($this->repository->hasActiveNameConflict(
            $table,
            $tenant['company_id'],
            $tenant['branch_id'],
            $name,
            $excludeId,
        )) {
            throw new HttpException('name_duplicate', 'Name already exists', 409);
        }
    }

    /** @param array<string, mixed> $row @return array<string, mixed> */
    private function createResponse(array $row): array
    {
        return [
            'id' => $row['id'],
            'row_version' => $row['row_version'],
            'created_at' => $row['created_at'] ?? null,
        ];
    }

    /** @param array<string, mixed> $row @return array<string, mixed> */
    private function patchResponse(array $row): array
    {
        return [
            'id' => $row['id'],
            'row_version' => $row['row_version'],
        ];
    }

    /** @param array<string, mixed> $existing @param array<string, mixed> $payload */
    private function isSameCategory(array $existing, array $payload): bool
    {
        return trim((string) ($payload['name'] ?? '')) === $existing['name']
            && (int) ($payload['sort_order'] ?? 0) === $existing['sort_order'];
    }

    /** @param array<string, mixed> $existing @param array<string, mixed> $payload */
    private function isSameUnit(array $existing, array $payload): bool
    {
        return trim((string) ($payload['name'] ?? '')) === $existing['name'];
    }

    /** @param array<string, mixed> $existing @param array<string, mixed> $payload */
    private function isSameTax(array $existing, array $payload): bool
    {
        return trim((string) ($payload['name'] ?? '')) === $existing['name']
            && (float) ($payload['percent'] ?? 0) === $existing['percent']
            && (bool) ($payload['is_default'] ?? false) === $existing['is_default']
            && (int) ($payload['sort_order'] ?? 0) === $existing['sort_order'];
    }

    /** @param array<string, mixed> $existing @param array<string, mixed> $payload */
    private function isSamePriceList(array $existing, array $payload): bool
    {
        return trim((string) ($payload['name'] ?? '')) === $existing['name']
            && (bool) ($payload['is_default'] ?? false) === $existing['is_default']
            && (int) ($payload['sort_order'] ?? 0) === $existing['sort_order'];
    }

    /** @return array{data: array<string, mixed>, meta: array<string, mixed>} */
    public function listCustomers(Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:read']);

        return $this->listResult(
            $this->repository->listCustomers(
                $tenant['company_id'],
                $tenant['branch_id'],
                $this->listFilters($request),
            ),
            $request,
        );
    }

    /**
     * @param array<string, mixed> $payload
     * @return array{data: array<string, mixed>, status: int}
     */
    public function createCustomer(array $payload, Request $request): array
    {
        return $this->createPartner('customers', $payload, $request);
    }

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function updateCustomer(string $id, array $payload, Request $request): array
    {
        return $this->updatePartner('customers', $id, $payload, $request);
    }

    /** @return array<string, mixed> */
    public function deleteCustomer(string $id, Request $request): array
    {
        return $this->deletePartner('customers', $id, $request);
    }

    /** @return array{data: array<string, mixed>, meta: array<string, mixed>} */
    public function listSuppliers(Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:read']);

        return $this->listResult(
            $this->repository->listSuppliers(
                $tenant['company_id'],
                $tenant['branch_id'],
                $this->listFilters($request),
            ),
            $request,
        );
    }

    /**
     * @param array<string, mixed> $payload
     * @return array{data: array<string, mixed>, status: int}
     */
    public function createSupplier(array $payload, Request $request): array
    {
        return $this->createPartner('suppliers', $payload, $request);
    }

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function updateSupplier(string $id, array $payload, Request $request): array
    {
        return $this->updatePartner('suppliers', $id, $payload, $request);
    }

    /** @return array<string, mixed> */
    public function deleteSupplier(string $id, Request $request): array
    {
        return $this->deletePartner('suppliers', $id, $request);
    }

    /** @return array{data: array<string, mixed>, meta: array<string, mixed>} */
    public function listSalesInvoices(Request $request): array
    {
        $tenant = $this->tenant($request, ['invoices:read']);

        return $this->listResult(
            $this->repository->listSalesInvoices(
                $tenant['company_id'],
                $tenant['branch_id'],
                $this->listFilters($request),
            ),
            $request,
        );
    }

    /**
     * @param array<string, mixed> $payload
     * @return array{data: array<string, mixed>, status: int}
     */
    public function createSalesInvoice(array $payload, Request $request): array
    {
        $tenant = $this->tenant($request, ['invoices:write']);
        $claims = $this->bearer->authenticate($request, ['invoices:write']);
        $userId = (string) ($claims['user_id'] ?? $claims['sub'] ?? '');
        if ($userId === '') {
            throw new HttpException('validation_error', 'User context required', 400);
        }

        $id = $this->resolveId($payload);
        $items = $payload['items'] ?? null;
        if (!is_array($items) || $items === []) {
            throw new HttpException('validation_error', 'items are required', 400);
        }

        $deviceId = (string) ($claims['device_id'] ?? $request->headers['X-Device-ID'] ?? $request->headers['x-device-id'] ?? '');

        try {
            $row = $this->repository->createSalesInvoiceDraft(
                $tenant['company_id'],
                $tenant['branch_id'],
                $id,
                $payload,
                $userId,
                $deviceId !== '' ? $deviceId : null,
            );
        } catch (PDOException $e) {
            if ($this->repository->isUniqueViolation($e)) {
                throw new HttpException('conflict', 'Invoice conflict', 409);
            }
            throw $e;
        }

        return ['status' => 201, 'data' => $row];
    }

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function updateSalesInvoice(string $id, array $payload, Request $request): array
    {
        $tenant = $this->tenant($request, ['invoices:write']);

        try {
            return $this->repository->updateSalesInvoiceDraft(
                $tenant['company_id'],
                $id,
                $payload,
            );
        } catch (PDOException $e) {
            if ($this->repository->isUniqueViolation($e)) {
                throw new HttpException('conflict', 'Invoice conflict', 409);
            }
            throw $e;
        }
    }

    /** @return array<string, mixed> */
    public function deleteSalesInvoice(string $id, Request $request): array
    {
        $tenant = $this->tenant($request, ['invoices:write']);

        return $this->repository->deleteSalesInvoiceDraft($tenant['company_id'], $id);
    }

    /**
     * @param array<string, mixed> $payload
     * @return array{data: array<string, mixed>, status: int}
     */
    private function createPartner(string $kind, array $payload, Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:write']);
        $name = trim((string) ($payload['name'] ?? ''));
        if ($name === '') {
            throw new HttpException('validation_error', 'name is required', 400);
        }

        $id = $this->resolveId($payload);
        $getter = $kind === 'customers' ? 'getCustomer' : 'getSupplier';
        $creator = $kind === 'customers' ? 'createCustomer' : 'createSupplier';
        $existing = $this->repository->{$getter}($tenant['company_id'], $id, true);
        if ($existing !== null && $existing['deleted_at'] === null) {
            throw new HttpException('conflict', 'Partner id already exists', 409);
        }

        $this->assertNameAvailable($kind, $tenant, $name);

        try {
            $row = $this->repository->{$creator}(
                $tenant['company_id'],
                $tenant['branch_id'],
                $id,
                $payload,
            );
        } catch (PDOException $e) {
            if ($this->repository->isUniqueViolation($e)) {
                throw new HttpException('name_duplicate', 'Partner name already exists', 409);
            }
            throw $e;
        }

        return ['status' => 201, 'data' => $this->createResponse($row)];
    }

    /** @param array<string, mixed> $payload @return array<string, mixed> */
    private function updatePartner(string $kind, string $id, array $payload, Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:write']);
        $getter = $kind === 'customers' ? 'getCustomer' : 'getSupplier';
        $updater = $kind === 'customers' ? 'updateCustomer' : 'updateSupplier';
        $existing = $this->requireEntity($this->repository->{$getter}($tenant['company_id'], $id));
        $this->assertRowVersion($existing, $payload);

        if (array_key_exists('name', $payload)) {
            $name = trim((string) $payload['name']);
            if ($name === '') {
                throw new HttpException('validation_error', 'name cannot be empty', 400);
            }
            $this->assertNameAvailable($kind, $tenant, $name, $id);
        }

        try {
            $row = $this->repository->{$updater}($tenant['company_id'], $id, $payload);
        } catch (PDOException $e) {
            if ($this->repository->isUniqueViolation($e)) {
                throw new HttpException('name_duplicate', 'Partner name already exists', 409);
            }
            throw $e;
        } catch (RuntimeException) {
            throw new HttpException('not_found', 'Partner not found', 404);
        }

        return $this->patchResponse($row);
    }

    /** @return array<string, mixed> */
    private function deletePartner(string $kind, string $id, Request $request): array
    {
        $tenant = $this->tenant($request, ['catalog:write']);
        $getter = $kind === 'customers' ? 'getCustomer' : 'getSupplier';
        $deleter = $kind === 'customers' ? 'softDeleteCustomer' : 'softDeleteSupplier';
        $this->requireEntity($this->repository->{$getter}($tenant['company_id'], $id));

        try {
            return $this->repository->{$deleter}($tenant['company_id'], $id);
        } catch (RuntimeException) {
            throw new HttpException('not_found', 'Partner not found', 404);
        }
    }
}
