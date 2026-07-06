<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync;

use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Database\Connection;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Core\Modules\ModuleInterface;
use MizaCloud\Core\Router\Router;
use MizaCloud\Modules\Devices\Support\BearerToken;
use MizaCloud\Modules\Sync\Controllers\CustomersSyncController;
use MizaCloud\Modules\Sync\Controllers\PriceListsSyncController;
use MizaCloud\Modules\Sync\Controllers\ProductCategoriesSyncController;
use MizaCloud\Modules\Sync\Controllers\ProductUnitsSyncController;
use MizaCloud\Modules\Sync\Controllers\ProductsSyncController;
use MizaCloud\Modules\Sync\Controllers\SuppliersSyncController;
use MizaCloud\Modules\Sync\Controllers\PurchaseInvoicesSyncController;
use MizaCloud\Modules\Sync\Controllers\PurchaseReturnsSyncController;
use MizaCloud\Modules\Sync\Controllers\SalesInvoicesSyncController;
use MizaCloud\Modules\Sync\Controllers\SalesReturnsSyncController;
use MizaCloud\Modules\Sync\Controllers\CustomerPaymentsSyncController;
use MizaCloud\Modules\Sync\Controllers\SupplierPaymentsSyncController;
use MizaCloud\Modules\Sync\Controllers\SyncController;
use MizaCloud\Modules\Sync\Controllers\TaxesSyncController;
use MizaCloud\Modules\Sync\Repositories\CustomersSyncRepository;
use MizaCloud\Modules\Sync\Repositories\PriceListsSyncRepository;
use MizaCloud\Modules\Sync\Repositories\ProductCategoriesSyncRepository;
use MizaCloud\Modules\Sync\Repositories\ProductUnitsSyncRepository;
use MizaCloud\Modules\Sync\Repositories\ProductsSyncRepository;
use MizaCloud\Modules\Sync\Repositories\SuppliersSyncRepository;
use MizaCloud\Modules\Sync\Repositories\PurchaseInvoicesSyncRepository;
use MizaCloud\Modules\Sync\Repositories\PurchaseReturnsSyncRepository;
use MizaCloud\Modules\Sync\Repositories\SalesInvoicesSyncRepository;
use MizaCloud\Modules\Sync\Repositories\SalesReturnsSyncRepository;
use MizaCloud\Modules\Sync\Repositories\CustomerPaymentsSyncRepository;
use MizaCloud\Modules\Sync\Repositories\SupplierPaymentsSyncRepository;
use MizaCloud\Modules\Sync\Repositories\SyncRepository;
use MizaCloud\Modules\Sync\Repositories\TaxesSyncRepository;
use MizaCloud\Modules\Sync\Services\CustomersSyncService;
use MizaCloud\Modules\Sync\Services\PriceListsSyncService;
use MizaCloud\Modules\Sync\Services\ProductCategoriesSyncService;
use MizaCloud\Modules\Sync\Services\ProductUnitsSyncService;
use MizaCloud\Modules\Sync\Services\ProductsSyncService;
use MizaCloud\Modules\Sync\Services\SuppliersSyncService;
use MizaCloud\Modules\Sync\Services\PurchaseInvoicesSyncService;
use MizaCloud\Modules\Sync\Services\PurchaseReturnsSyncService;
use MizaCloud\Modules\Sync\Services\SalesInvoicesSyncService;
use MizaCloud\Modules\Sync\Services\SalesReturnsSyncService;
use MizaCloud\Modules\Sync\Services\CustomerPaymentsSyncService;
use MizaCloud\Modules\Sync\Services\SupplierPaymentsSyncService;
use MizaCloud\Modules\Sync\Services\SyncService;
use MizaCloud\Modules\Sync\Services\TaxesSyncService;

final class SyncModule implements ModuleInterface
{
    public function name(): string
    {
        return 'sync';
    }

    public function register(Container $container): void
    {
        $container->singleton(SyncRepository::class, static fn ($c) => new SyncRepository($c->get(Connection::class)));

        $container->singleton(ProductsSyncRepository::class, static fn ($c) => new ProductsSyncRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(ProductCategoriesSyncRepository::class, static fn ($c) => new ProductCategoriesSyncRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(ProductUnitsSyncRepository::class, static fn ($c) => new ProductUnitsSyncRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(TaxesSyncRepository::class, static fn ($c) => new TaxesSyncRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(PriceListsSyncRepository::class, static fn ($c) => new PriceListsSyncRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(CustomersSyncRepository::class, static fn ($c) => new CustomersSyncRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(SuppliersSyncRepository::class, static fn ($c) => new SuppliersSyncRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(PurchaseInvoicesSyncRepository::class, static fn ($c) => new PurchaseInvoicesSyncRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(SalesInvoicesSyncRepository::class, static fn ($c) => new SalesInvoicesSyncRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(SalesReturnsSyncRepository::class, static fn ($c) => new SalesReturnsSyncRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(PurchaseReturnsSyncRepository::class, static fn ($c) => new PurchaseReturnsSyncRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(CustomerPaymentsSyncRepository::class, static fn ($c) => new CustomerPaymentsSyncRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(SupplierPaymentsSyncRepository::class, static fn ($c) => new SupplierPaymentsSyncRepository(
            $c->get(Connection::class),
        ));

        $bearer = static fn ($c) => $c->get(BearerToken::class);
        $logger = static fn ($c) => $c->get(Logger::class);

        $container->singleton(ProductsSyncService::class, static fn ($c) => new ProductsSyncService(
            repository: $c->get(ProductsSyncRepository::class),
            bearer: $c->get(BearerToken::class),
            logger: $c->get(Logger::class),
        ));

        $container->singleton(ProductCategoriesSyncService::class, static fn ($c) => new ProductCategoriesSyncService(
            repository: $c->get(ProductCategoriesSyncRepository::class),
            bearer: $c->get(BearerToken::class),
            logger: $c->get(Logger::class),
        ));

        $container->singleton(ProductUnitsSyncService::class, static fn ($c) => new ProductUnitsSyncService(
            repository: $c->get(ProductUnitsSyncRepository::class),
            bearer: $c->get(BearerToken::class),
            logger: $c->get(Logger::class),
        ));

        $container->singleton(TaxesSyncService::class, static fn ($c) => new TaxesSyncService(
            repository: $c->get(TaxesSyncRepository::class),
            bearer: $c->get(BearerToken::class),
            logger: $c->get(Logger::class),
        ));

        $container->singleton(PriceListsSyncService::class, static fn ($c) => new PriceListsSyncService(
            repository: $c->get(PriceListsSyncRepository::class),
            bearer: $c->get(BearerToken::class),
            logger: $c->get(Logger::class),
        ));

        $container->singleton(CustomersSyncService::class, static fn ($c) => new CustomersSyncService(
            repository: $c->get(CustomersSyncRepository::class),
            bearer: $c->get(BearerToken::class),
            logger: $c->get(Logger::class),
        ));

        $container->singleton(SuppliersSyncService::class, static fn ($c) => new SuppliersSyncService(
            repository: $c->get(SuppliersSyncRepository::class),
            bearer: $c->get(BearerToken::class),
            logger: $c->get(Logger::class),
        ));

        $container->singleton(PurchaseInvoicesSyncService::class, static fn ($c) => new PurchaseInvoicesSyncService(
            repository: $c->get(PurchaseInvoicesSyncRepository::class),
            bearer: $c->get(BearerToken::class),
            logger: $c->get(Logger::class),
        ));

        $container->singleton(SalesInvoicesSyncService::class, static fn ($c) => new SalesInvoicesSyncService(
            repository: $c->get(SalesInvoicesSyncRepository::class),
            bearer: $c->get(BearerToken::class),
            logger: $c->get(Logger::class),
        ));

        $container->singleton(SalesReturnsSyncService::class, static fn ($c) => new SalesReturnsSyncService(
            repository: $c->get(SalesReturnsSyncRepository::class),
            bearer: $c->get(BearerToken::class),
            logger: $c->get(Logger::class),
        ));

        $container->singleton(PurchaseReturnsSyncService::class, static fn ($c) => new PurchaseReturnsSyncService(
            repository: $c->get(PurchaseReturnsSyncRepository::class),
            bearer: $c->get(BearerToken::class),
            logger: $c->get(Logger::class),
        ));

        $container->singleton(CustomerPaymentsSyncService::class, static fn ($c) => new CustomerPaymentsSyncService(
            repository: $c->get(CustomerPaymentsSyncRepository::class),
            bearer: $c->get(BearerToken::class),
            logger: $c->get(Logger::class),
        ));

        $container->singleton(SupplierPaymentsSyncService::class, static fn ($c) => new SupplierPaymentsSyncService(
            repository: $c->get(SupplierPaymentsSyncRepository::class),
            bearer: $c->get(BearerToken::class),
            logger: $c->get(Logger::class),
        ));

        $container->singleton(SyncService::class, static fn ($c) => new SyncService($c->get(SyncRepository::class)));

        $container->singleton(ProductsSyncController::class, static fn ($c) => new ProductsSyncController(
            $c->get(ResponseBuilder::class),
            $c->get(ProductsSyncService::class),
        ));

        $container->singleton(ProductCategoriesSyncController::class, static fn ($c) => new ProductCategoriesSyncController(
            $c->get(ResponseBuilder::class),
            $c->get(ProductCategoriesSyncService::class),
        ));

        $container->singleton(ProductUnitsSyncController::class, static fn ($c) => new ProductUnitsSyncController(
            $c->get(ResponseBuilder::class),
            $c->get(ProductUnitsSyncService::class),
        ));

        $container->singleton(TaxesSyncController::class, static fn ($c) => new TaxesSyncController(
            $c->get(ResponseBuilder::class),
            $c->get(TaxesSyncService::class),
        ));

        $container->singleton(PriceListsSyncController::class, static fn ($c) => new PriceListsSyncController(
            $c->get(ResponseBuilder::class),
            $c->get(PriceListsSyncService::class),
        ));

        $container->singleton(CustomersSyncController::class, static fn ($c) => new CustomersSyncController(
            $c->get(ResponseBuilder::class),
            $c->get(CustomersSyncService::class),
        ));

        $container->singleton(SuppliersSyncController::class, static fn ($c) => new SuppliersSyncController(
            $c->get(ResponseBuilder::class),
            $c->get(SuppliersSyncService::class),
        ));

        $container->singleton(PurchaseInvoicesSyncController::class, static fn ($c) => new PurchaseInvoicesSyncController(
            $c->get(ResponseBuilder::class),
            $c->get(PurchaseInvoicesSyncService::class),
        ));

        $container->singleton(SalesInvoicesSyncController::class, static fn ($c) => new SalesInvoicesSyncController(
            $c->get(ResponseBuilder::class),
            $c->get(SalesInvoicesSyncService::class),
        ));

        $container->singleton(SalesReturnsSyncController::class, static fn ($c) => new SalesReturnsSyncController(
            $c->get(ResponseBuilder::class),
            $c->get(SalesReturnsSyncService::class),
        ));

        $container->singleton(PurchaseReturnsSyncController::class, static fn ($c) => new PurchaseReturnsSyncController(
            $c->get(ResponseBuilder::class),
            $c->get(PurchaseReturnsSyncService::class),
        ));

        $container->singleton(CustomerPaymentsSyncController::class, static fn ($c) => new CustomerPaymentsSyncController(
            $c->get(ResponseBuilder::class),
            $c->get(CustomerPaymentsSyncService::class),
        ));

        $container->singleton(SupplierPaymentsSyncController::class, static fn ($c) => new SupplierPaymentsSyncController(
            $c->get(ResponseBuilder::class),
            $c->get(SupplierPaymentsSyncService::class),
        ));

        $container->singleton(SyncController::class, static fn ($c) => new SyncController(
            $c->get(ResponseBuilder::class),
            $c->get(SyncService::class),
        ));
    }

    public function routes(Router $router): void
    {
        $catalogRoutes = [
            ['products', ProductsSyncController::class, 'pushProducts', 'pullProducts'],
            ['product-categories', ProductCategoriesSyncController::class, 'push', 'pull'],
            ['product-units', ProductUnitsSyncController::class, 'push', 'pull'],
            ['taxes', TaxesSyncController::class, 'push', 'pull'],
            ['price-lists', PriceListsSyncController::class, 'push', 'pull'],
            ['customers', CustomersSyncController::class, 'push', 'pull'],
            ['suppliers', SuppliersSyncController::class, 'push', 'pull'],
            ['sales-invoices', SalesInvoicesSyncController::class, 'push', 'pull'],
            ['purchase-invoices', PurchaseInvoicesSyncController::class, 'push', 'pull'],
            ['sales-returns', SalesReturnsSyncController::class, 'push', 'pull'],
            ['purchase-returns', PurchaseReturnsSyncController::class, 'push', 'pull'],
            ['customer-payments', CustomerPaymentsSyncController::class, 'push', 'pull'],
            ['supplier-payments', SupplierPaymentsSyncController::class, 'push', 'pull'],
        ];

        foreach ($this->prefixes() as $prefix) {
            foreach ($catalogRoutes as [$segment, $controller, $pushMethod, $pullMethod]) {
                $router->post("{$prefix}/push/{$segment}", [$controller, $pushMethod]);
                $router->get("{$prefix}/pull/{$segment}", [$controller, $pullMethod]);
            }
        }
    }

    /** @return list<string> */
    private function prefixes(): array
    {
        return ['/v1/sync', '/sync'];
    }
}
