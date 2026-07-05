<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Notifications;

use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Database\Connection;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Core\Modules\ModuleInterface;
use MizaCloud\Core\Router\Router;
use MizaCloud\Modules\Notifications\Controllers\NotificationController;
use MizaCloud\Modules\Notifications\Repositories\NotificationRepository;
use MizaCloud\Modules\Notifications\Services\NotificationService;

final class NotificationsModule implements ModuleInterface
{
    public function name(): string { return 'notifications'; }

    public function register(Container $container): void
    {
        $container->singleton(NotificationRepository::class, static fn ($c) => new NotificationRepository($c->get(Connection::class)));
        $container->singleton(NotificationService::class, static fn ($c) => new NotificationService($c->get(NotificationRepository::class)));
        $container->singleton(NotificationController::class, static fn ($c) => new NotificationController($c->get(ResponseBuilder::class), $c->get(NotificationService::class)));
    }

    public function routes(Router $router): void {}
}
