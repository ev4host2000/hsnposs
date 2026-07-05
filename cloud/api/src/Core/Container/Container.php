<?php

declare(strict_types=1);

namespace MizaCloud\Core\Container;

use Closure;
use RuntimeException;

/**
 * حاوية تبعيات بسيطة — register / singleton / resolve.
 */
final class Container
{
    /** @var array<string, mixed> */
    private array $bindings = [];

    /** @var array<string, object> */
    private array $instances = [];

    public function bind(string $abstract, Closure $concrete): void
    {
        $this->bindings[$abstract] = $concrete;
    }

    public function singleton(string $abstract, Closure $concrete): void
    {
        $this->bind($abstract, function (Container $container) use ($abstract, $concrete) {
            if (!isset($this->instances[$abstract])) {
                $this->instances[$abstract] = $concrete($container);
            }
            return $this->instances[$abstract];
        });
    }

    public function instance(string $abstract, object $instance): void
    {
        $this->instances[$abstract] = $instance;
    }

    public function has(string $abstract): bool
    {
        return isset($this->instances[$abstract]) || isset($this->bindings[$abstract]);
    }

    public function get(string $abstract): mixed
    {
        if (isset($this->instances[$abstract])) {
            return $this->instances[$abstract];
        }

        if (!isset($this->bindings[$abstract])) {
            throw new RuntimeException("Binding not found: {$abstract}");
        }

        $resolved = $this->bindings[$abstract]($this);
        if (is_object($resolved)) {
            $this->instances[$abstract] = $resolved;
        }
        return $resolved;
    }
}
