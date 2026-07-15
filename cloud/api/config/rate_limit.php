<?php

declare(strict_types=1);

return [
    'enabled' => filter_var($_ENV['RATE_LIMIT_ENABLED'] ?? true, FILTER_VALIDATE_BOOL),
    'login_max_attempts' => (int) ($_ENV['RATE_LIMIT_LOGIN_MAX'] ?? 10),
    'login_window_seconds' => (int) ($_ENV['RATE_LIMIT_LOGIN_WINDOW'] ?? 60),
    // RAP-P1-03: tighter limit for forgot-password (SMTP cost / abuse)
    'forgot_max_attempts' => (int) ($_ENV['RATE_LIMIT_FORGOT_MAX'] ?? 5),
    'forgot_window_seconds' => (int) ($_ENV['RATE_LIMIT_FORGOT_WINDOW'] ?? 300),
    'storage_path' => $_ENV['RATE_LIMIT_STORAGE'] ?? 'storage/rate_limit',
    // RAP-P1-01: honor X-Forwarded-For / X-Real-IP only when REMOTE_ADDR is a trusted proxy.
    'trust_proxy' => filter_var($_ENV['RATE_LIMIT_TRUST_PROXY'] ?? true, FILTER_VALIDATE_BOOL),
    'trusted_proxies' => array_values(array_filter(array_map(
        static fn (string $v): string => trim($v),
        explode(',', (string) ($_ENV['RATE_LIMIT_TRUSTED_PROXIES'] ?? '127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16')),
    ))),
];
