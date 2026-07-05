<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Catalog\Controllers;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Controller;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Modules\Catalog\Services\CatalogService;

final class CatalogController extends Controller
{
    public function __construct(
        ResponseBuilder $responses,
        private readonly CatalogService $service,
    ) {
        parent::__construct($responses);
    }

    public function listProductCategories(Request $request): Response
    {
        $result = $this->service->listProductCategories($request);

        return $this->responses->success($result['data'], meta: $result['meta']);
    }

    public function createProductCategory(Request $request): Response
    {
        $result = $this->service->createProductCategory($this->jsonBody($request), $request);

        return $this->responses->success($result['data'], status: $result['status']);
    }

    public function updateProductCategory(Request $request): Response
    {
        $id = (string) $request->attribute('id', '');
        $data = $this->service->updateProductCategory($id, $this->jsonBody($request), $request);

        return $this->responses->success($data);
    }

    public function deleteProductCategory(Request $request): Response
    {
        $id = (string) $request->attribute('id', '');
        $data = $this->service->deleteProductCategory($id, $request);

        return $this->responses->success($data);
    }

    public function listProductUnits(Request $request): Response
    {
        $result = $this->service->listProductUnits($request);

        return $this->responses->success($result['data'], meta: $result['meta']);
    }

    public function createProductUnit(Request $request): Response
    {
        $result = $this->service->createProductUnit($this->jsonBody($request), $request);

        return $this->responses->success($result['data'], status: $result['status']);
    }

    public function updateProductUnit(Request $request): Response
    {
        $id = (string) $request->attribute('id', '');
        $data = $this->service->updateProductUnit($id, $this->jsonBody($request), $request);

        return $this->responses->success($data);
    }

    public function deleteProductUnit(Request $request): Response
    {
        $id = (string) $request->attribute('id', '');
        $data = $this->service->deleteProductUnit($id, $request);

        return $this->responses->success($data);
    }

    public function listTaxes(Request $request): Response
    {
        $result = $this->service->listTaxes($request);

        return $this->responses->success($result['data'], meta: $result['meta']);
    }

    public function createTax(Request $request): Response
    {
        $result = $this->service->createTax($this->jsonBody($request), $request);

        return $this->responses->success($result['data'], status: $result['status']);
    }

    public function updateTax(Request $request): Response
    {
        $id = (string) $request->attribute('id', '');
        $data = $this->service->updateTax($id, $this->jsonBody($request), $request);

        return $this->responses->success($data);
    }

    public function deleteTax(Request $request): Response
    {
        $id = (string) $request->attribute('id', '');
        $data = $this->service->deleteTax($id, $request);

        return $this->responses->success($data);
    }

    public function listPriceLists(Request $request): Response
    {
        $result = $this->service->listPriceLists($request);

        return $this->responses->success($result['data'], meta: $result['meta']);
    }

    public function createPriceList(Request $request): Response
    {
        $result = $this->service->createPriceList($this->jsonBody($request), $request);

        return $this->responses->success($result['data'], status: $result['status']);
    }

    public function updatePriceList(Request $request): Response
    {
        $id = (string) $request->attribute('id', '');
        $data = $this->service->updatePriceList($id, $this->jsonBody($request), $request);

        return $this->responses->success($data);
    }

    public function deletePriceList(Request $request): Response
    {
        $id = (string) $request->attribute('id', '');
        $data = $this->service->deletePriceList($id, $request);

        return $this->responses->success($data);
    }

    public function listCustomers(Request $request): Response
    {
        $result = $this->service->listCustomers($request);

        return $this->responses->success($result['data'], meta: $result['meta']);
    }

    public function createCustomer(Request $request): Response
    {
        $result = $this->service->createCustomer($this->jsonBody($request), $request);

        return $this->responses->success($result['data'], status: $result['status']);
    }

    public function updateCustomer(Request $request): Response
    {
        $id = (string) $request->attribute('id', '');
        $data = $this->service->updateCustomer($id, $this->jsonBody($request), $request);

        return $this->responses->success($data);
    }

    public function deleteCustomer(Request $request): Response
    {
        $id = (string) $request->attribute('id', '');
        $data = $this->service->deleteCustomer($id, $request);

        return $this->responses->success($data);
    }

    public function listSuppliers(Request $request): Response
    {
        $result = $this->service->listSuppliers($request);

        return $this->responses->success($result['data'], meta: $result['meta']);
    }

    public function createSupplier(Request $request): Response
    {
        $result = $this->service->createSupplier($this->jsonBody($request), $request);

        return $this->responses->success($result['data'], status: $result['status']);
    }

    public function updateSupplier(Request $request): Response
    {
        $id = (string) $request->attribute('id', '');
        $data = $this->service->updateSupplier($id, $this->jsonBody($request), $request);

        return $this->responses->success($data);
    }

    public function deleteSupplier(Request $request): Response
    {
        $id = (string) $request->attribute('id', '');
        $data = $this->service->deleteSupplier($id, $request);

        return $this->responses->success($data);
    }

    public function listSalesInvoices(Request $request): Response
    {
        $result = $this->service->listSalesInvoices($request);

        return $this->responses->success($result['data'], meta: $result['meta']);
    }

    public function createSalesInvoice(Request $request): Response
    {
        $result = $this->service->createSalesInvoice($this->jsonBody($request), $request);

        return $this->responses->success($result['data'], status: $result['status']);
    }

    public function updateSalesInvoice(Request $request): Response
    {
        $id = (string) $request->attribute('id', '');
        $data = $this->service->updateSalesInvoice($id, $this->jsonBody($request), $request);

        return $this->responses->success($data);
    }

    public function deleteSalesInvoice(Request $request): Response
    {
        $id = (string) $request->attribute('id', '');
        $data = $this->service->deleteSalesInvoice($id, $request);

        return $this->responses->success($data);
    }

    /** @return array<string, mixed> */
    private function jsonBody(Request $request): array
    {
        if ($request->body === null || trim($request->body) === '') {
            return [];
        }

        $decoded = json_decode($request->body, true);
        if (!is_array($decoded)) {
            throw new HttpException('validation_error', 'Invalid JSON body', 400);
        }

        return $decoded;
    }
}
