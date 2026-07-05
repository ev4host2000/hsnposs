<?php

declare(strict_types=1);

namespace MizaCloud\Core\Logging;

/**
 * Logger بسيط إلى ملف — بدون تبعيات خارجية.
 */
final class Logger
{
    public function __construct(
        private readonly string $logPath,
        private readonly string $minLevel = 'info',
    ) {}

    public function debug(string $message, array $context = []): void
    {
        $this->log('debug', $message, $context);
    }

    public function info(string $message, array $context = []): void
    {
        $this->log('info', $message, $context);
    }

    public function warning(string $message, array $context = []): void
    {
        $this->log('warning', $message, $context);
    }

    public function error(string $message, array $context = []): void
    {
        $this->log('error', $message, $context);
    }

    public function log(string $level, string $message, array $context = []): void
    {
        if (!is_dir($this->logPath)) {
            @mkdir($this->logPath, 0775, true);
        }

        $line = json_encode([
            'time' => gmdate('c'),
            'level' => $level,
            'message' => $message,
            'context' => $context,
        ], JSON_UNESCAPED_UNICODE);

        if ($line === false) {
            return;
        }

        $file = rtrim($this->logPath, '/\\') . DIRECTORY_SEPARATOR . 'app.log';
        @file_put_contents($file, $line . PHP_EOL, FILE_APPEND | LOCK_EX);
    }
}
