<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Media;

use MizaCloud\Core\Config\Config;
use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Database\Connection;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Core\Modules\ModuleInterface;
use MizaCloud\Core\Router\Router;
use MizaCloud\Modules\Auth\Services\JwtService;
use MizaCloud\Modules\Devices\Repositories\DeviceRepository;
use MizaCloud\Modules\Devices\Support\BearerToken;
use MizaCloud\Modules\Media\Controllers\ProductMediaController;
use MizaCloud\Modules\Media\Repositories\ProductMediaRepository;
use MizaCloud\Modules\Media\Services\ProductMediaService;

final class MediaModule implements ModuleInterface
{
    public function name(): string
    {
        return 'media';
    }

    public function register(Container $container): void
    {
        $container->singleton(ProductMediaRepository::class, static fn ($c) => new ProductMediaRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(ProductMediaService::class, static function (Container $c): ProductMediaService {
            $basePath = dirname(__DIR__, 3);

            return new ProductMediaService(
                repository: $c->get(ProductMediaRepository::class),
                bearer: $c->get(BearerToken::class),
                config: $c->get(Config::class),
                logger: $c->get(Logger::class),
                storageRoot: $basePath . '/storage/media',
            );
        });

        $container->singleton(ProductMediaController::class, static fn ($c) => new ProductMediaController(
            $c->get(ResponseBuilder::class),
            $c->get(ProductMediaService::class),
        ));

        if (!$container->has(BearerToken::class)) {
            $container->singleton(BearerToken::class, static fn ($c) => new BearerToken(
                $c->get(JwtService::class),
                $c->get(DeviceRepository::class),
            ));
        }
    }

    public function routes(Router $router): void
    {
        $controller = ProductMediaController::class;

        foreach ($this->prefixes() as $prefix) {
            $router->post("{$prefix}/products/{productId}", [$controller, 'uploadProductImage']);
        }
    }

    /** @return list<string> */
    private function prefixes(): array
    {
        return ['/v1/media', '/media'];
    }
}
