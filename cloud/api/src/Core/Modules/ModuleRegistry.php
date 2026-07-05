<?php

declare(strict_types=1);

namespace MizaCloud\Core\Modules;

use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Router\Router;
use MizaCloud\Modules\Auth\AuthModule;
use MizaCloud\Modules\Branches\BranchesModule;
use MizaCloud\Modules\Catalog\CatalogModule;
use MizaCloud\Modules\Companies\CompaniesModule;
use MizaCloud\Modules\Conflicts\ConflictsModule;
use MizaCloud\Modules\Devices\DevicesModule;
use MizaCloud\Modules\Health\HealthModule;
use MizaCloud\Modules\Invoices\InvoicesModule;
use MizaCloud\Modules\Notifications\NotificationsModule;
use MizaCloud\Modules\Sync\SyncModule;
use MizaCloud\Modules\Users\UsersModule;

/**
 * يحمّل كل Modules ويسجّلها.
 */
final class ModuleRegistry
{
    public static function registerAll(Container $container, Router $router): void
    {
        $modules = [
            new HealthModule(),
            new AuthModule(),
            new DevicesModule(),
            new CompaniesModule(),
            new BranchesModule(),
            new UsersModule(),
            new CatalogModule(),
            new InvoicesModule(),
            new SyncModule(),
            new ConflictsModule(),
            new NotificationsModule(),
        ];

        foreach ($modules as $module) {
            $module->register($container);
            $module->routes($router);
        }
    }
}
