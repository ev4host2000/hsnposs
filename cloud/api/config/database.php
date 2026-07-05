<?php

declare(strict_types=1);

return [
    'driver' => 'pgsql',
    'host' => $_ENV['DB_HOST'] ?? '127.0.0.1',
    'port' => (int) ($_ENV['DB_PORT'] ?? 5432),
    'database' => $_ENV['DB_NAME'] ?? 'mizacloud',
    'username' => $_ENV['DB_USER'] ?? 'mizacloud',
    'password' => $_ENV['DB_PASSWORD'] ?? '',
    'charset' => 'utf8',
    'options' => [],
];
