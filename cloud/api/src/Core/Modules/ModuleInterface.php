<?php

declare(strict_types=1);

namespace MizaCloud\Core\Modules;

use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Router\Router;

/**
 * عقد كل Module مستقل.
 */
interface ModuleInterface
{
    public function name(): string;

    /** تسجيل bindings في Container */
    public function register(Container $container): void;

    /** تسجيل routes — فارغ في هذه المرحلة */
    public function routes(Router $router): void;
}
