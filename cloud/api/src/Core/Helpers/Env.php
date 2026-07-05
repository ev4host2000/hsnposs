<?php

declare(strict_types=1);

namespace MizaCloud\Core\Helpers;

/**
 * قراءة متغيرات البيئة من .env — بدون مكتبات خارجية.
 */
final class Env
{
    public static function load(string $basePath): void
    {
        $file = rtrim($basePath, '/\\') . DIRECTORY_SEPARATOR . '.env';
        if (!is_file($file)) {
            return;
        }

        $lines = file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        if ($lines === false) {
            return;
        }

        foreach ($lines as $line) {
            $line = trim($line);
            if ($line === '' || str_starts_with($line, '#')) {
                continue;
            }
            $pos = strpos($line, '=');
            if ($pos === false) {
                continue;
            }
            $key = trim(substr($line, 0, $pos));
            $value = trim(substr($line, $pos + 1));
            if ($key !== '' && !array_key_exists($key, $_ENV)) {
                $_ENV[$key] = $value;
                putenv("{$key}={$value}");
            }
        }
    }
}
