<?php

declare(strict_types=1);

namespace MizaCloud\Core\Config;

/**
 * تحميل ملفات config/*.php — بدون منطق أعمال.
 */
final class Config
{
    /** @var array<string, array<string, mixed>> */
    private array $items = [];

    public function __construct(private readonly string $configPath) {}

    public static function loadFromPath(string $configPath): self
    {
        $instance = new self($configPath);
        $instance->loadAll();
        return $instance;
    }

    private function loadAll(): void
    {
        if (!is_dir($this->configPath)) {
            return;
        }

        foreach (glob($this->configPath . '/*.php') ?: [] as $file) {
            $key = basename($file, '.php');
            $value = require $file;
            if (is_array($value)) {
                $this->items[$key] = $value;
            }
        }
    }

  /**
   * @return array<string, mixed>
   */
    public function get(string $key, mixed $default = null): mixed
    {
        return $this->items[$key] ?? $default;
    }

    public function getString(string $file, string $key, string $default = ''): string
    {
        $section = $this->get($file, []);
        if (!is_array($section)) {
            return $default;
        }
        $value = $section[$key] ?? $default;
        return is_string($value) ? $value : (string) $value;
    }
}
