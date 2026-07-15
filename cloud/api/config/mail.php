<?php

declare(strict_types=1);

$enabled = filter_var($_ENV['MAIL_ENABLED'] ?? 'false', FILTER_VALIDATE_BOOLEAN);

return [
    'enabled' => $enabled,
    'host' => trim((string) ($_ENV['MAIL_HOST'] ?? '')),
    'port' => (int) ($_ENV['MAIL_PORT'] ?? 587),
    'encryption' => strtolower(trim((string) ($_ENV['MAIL_ENCRYPTION'] ?? 'tls'))),
    'username' => trim((string) ($_ENV['MAIL_USERNAME'] ?? '')),
    'password' => (string) ($_ENV['MAIL_PASSWORD'] ?? ''),
    'from_address' => trim((string) ($_ENV['MAIL_FROM_ADDRESS'] ?? 'info@mizapos.com')),
    'from_name' => trim((string) ($_ENV['MAIL_FROM_NAME'] ?? 'MizaPos Cloud')),
    'reply_to' => trim((string) ($_ENV['MAIL_REPLY_TO'] ?? 'info@mizapos.com')),
];
