<?php

declare(strict_types=1);

return [
    'name' => 'Miza Cloud API',
    'env' => $_ENV['APP_ENV'] ?? 'production',
    'debug' => filter_var($_ENV['APP_DEBUG'] ?? false, FILTER_VALIDATE_BOOL),
    'url' => $_ENV['APP_URL'] ?? 'https://api.mizapos.com',
    'timezone' => $_ENV['APP_TIMEZONE'] ?? 'UTC',
    'api_version' => 'v1',
];
