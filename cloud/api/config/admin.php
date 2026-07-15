<?php

declare(strict_types=1);

return [
    'email' => $_ENV['OPS_ADMIN_EMAIL'] ?? '',
    'password_hash' => $_ENV['OPS_ADMIN_PASSWORD_HASH'] ?? '',
    'access_ttl' => (int) ($_ENV['OPS_ADMIN_ACCESS_TTL'] ?? 3600),
];
