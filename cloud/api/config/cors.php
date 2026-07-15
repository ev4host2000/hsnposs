<?php

declare(strict_types=1);

return [
    'allowed_origins' => array_values(array_filter(array_map(
        static fn (string $o): string => trim($o),
        explode(',', (string) ($_ENV['CORS_ALLOWED_ORIGINS'] ?? '*')),
    ))),
    'allowed_methods' => ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    'allowed_headers' => [
        'Authorization',
        'Content-Type',
        'Accept',
        'Accept-Encoding',
        'X-Request-Id',
        'User-Agent',
    ],
    'max_age' => 86400,
    'allow_credentials' => filter_var($_ENV['CORS_ALLOW_CREDENTIALS'] ?? false, FILTER_VALIDATE_BOOL),
];
