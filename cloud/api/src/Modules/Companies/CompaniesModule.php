<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Companies;

use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Database\Connection;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Core\Modules\ModuleInterface;
use MizaCloud\Core\Router\Router;
use MizaCloud\Modules\Companies\Controllers\CompanyController;
use MizaCloud\Modules\Companies\Repositories\CompanyRepository;
use MizaCloud\Modules\Companies\Services\CompanyService;

final class CompaniesModule implements ModuleInterface
{
    public function name(): string { return 'companies'; }

    public function register(Container $container): void
    {
        $container->singleton(CompanyRepository::class, static fn ($c) => new CompanyRepository($c->get(Connection::class)));
        $container->singleton(CompanyService::class, static fn ($c) => new CompanyService($c->get(CompanyRepository::class)));
        $container->singleton(CompanyController::class, static fn ($c) => new CompanyController($c->get(ResponseBuilder::class), $c->get(CompanyService::class)));
    }

    public function routes(Router $router): void {}
}
