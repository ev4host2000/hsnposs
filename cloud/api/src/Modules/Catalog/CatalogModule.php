<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Catalog;

use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Database\Connection;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Core\Modules\ModuleInterface;
use MizaCloud\Core\Router\Router;
use MizaCloud\Modules\Catalog\Controllers\CatalogController;
use MizaCloud\Modules\Catalog\Repositories\CatalogRepository;
use MizaCloud\Modules\Catalog\Services\CatalogService;
use MizaCloud\Modules\Devices\Support\BearerToken;

final class CatalogModule implements ModuleInterface
{
    public function name(): string
    {
        return 'catalog';
    }

    public function register(Container $container): void
    {
        $container->singleton(CatalogRepository::class, static fn ($c) => new CatalogRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(CatalogService::class, static fn ($c) => new CatalogService(
            $c->get(CatalogRepository::class),
            $c->get(BearerToken::class),
        ));

        $container->singleton(CatalogController::class, static fn ($c) => new CatalogController(
            $c->get(ResponseBuilder::class),
            $c->get(CatalogService::class),
        ));
    }

    public function routes(Router $router): void
    {
        $controller = CatalogController::class;

        $catalogRoutes = [
            ['product-categories', 'listProductCategories', 'createProductCategory', 'updateProductCategory', 'deleteProductCategory'],
            ['product-units', 'listProductUnits', 'createProductUnit', 'updateProductUnit', 'deleteProductUnit'],
            ['taxes', 'listTaxes', 'createTax', 'updateTax', 'deleteTax'],
            ['price-lists', 'listPriceLists', 'createPriceList', 'updatePriceList', 'deletePriceList'],
            ['customers', 'listCustomers', 'createCustomer', 'updateCustomer', 'deleteCustomer'],
            ['suppliers', 'listSuppliers', 'createSupplier', 'updateSupplier', 'deleteSupplier'],
            ['sales-invoices', 'listSalesInvoices', 'createSalesInvoice', 'updateSalesInvoice', 'deleteSalesInvoice'],
        ];

        foreach ($this->prefixes() as $prefix) {
            foreach ($catalogRoutes as [$segment, $list, $create, $update, $delete]) {
                $router->get("{$prefix}/{$segment}", [$controller, $list]);
                $router->post("{$prefix}/{$segment}", [$controller, $create]);
                $router->patch("{$prefix}/{$segment}/{id}", [$controller, $update]);
                $router->delete("{$prefix}/{$segment}/{id}", [$controller, $delete]);
            }
        }
    }

    /** @return list<string> */
    private function prefixes(): array
    {
        return ['/v1', ''];
    }
}
