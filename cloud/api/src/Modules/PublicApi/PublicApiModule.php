<?php

declare(strict_types=1);

namespace MizaCloud\Modules\PublicApi;

use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Database\Connection;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Core\Modules\ModuleInterface;
use MizaCloud\Core\Router\Router;
use MizaCloud\Modules\Admin\Repositories\AdminBetaRepository;
use MizaCloud\Modules\Admin\Repositories\AdminRepository;
use MizaCloud\Modules\PublicApi\Controllers\PublicBetaController;
use MizaCloud\Modules\PublicApi\Services\PublicBetaService;

final class PublicApiModule implements ModuleInterface
{
    public function name(): string
    {
        return 'public_api';
    }

    public function register(Container $container): void
    {
        $container->singleton(AdminBetaRepository::class, static fn ($c) => new AdminBetaRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(AdminRepository::class, static fn ($c) => new AdminRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(PublicBetaService::class, static fn ($c) => new PublicBetaService(
            $c->get(AdminBetaRepository::class),
            $c->get(AdminRepository::class),
        ));

        $container->singleton(PublicBetaController::class, static fn ($c) => new PublicBetaController(
            $c->get(ResponseBuilder::class),
            $c->get(PublicBetaService::class),
        ));
    }

    public function routes(Router $router): void
    {
        $controller = PublicBetaController::class;

        foreach (['/v1/public', '/public'] as $prefix) {
            $router->post("{$prefix}/beta-signup", [$controller, 'signup']);
            $router->post("{$prefix}/voucher/validate", [$controller, 'validateVoucher']);
        }
    }
}
