<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Invoices;

use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Database\Connection;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Core\Modules\ModuleInterface;
use MizaCloud\Core\Router\Router;
use MizaCloud\Modules\Invoices\Controllers\InvoiceController;
use MizaCloud\Modules\Invoices\Repositories\InvoiceRepository;
use MizaCloud\Modules\Invoices\Services\InvoiceService;

final class InvoicesModule implements ModuleInterface
{
    public function name(): string { return 'invoices'; }

    public function register(Container $container): void
    {
        $container->singleton(InvoiceRepository::class, static fn ($c) => new InvoiceRepository($c->get(Connection::class)));
        $container->singleton(InvoiceService::class, static fn ($c) => new InvoiceService($c->get(InvoiceRepository::class)));
        $container->singleton(InvoiceController::class, static fn ($c) => new InvoiceController($c->get(ResponseBuilder::class), $c->get(InvoiceService::class)));
    }

    public function routes(Router $router): void {}
}
