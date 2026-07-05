<?php

declare(strict_types=1);

return [
    'secret' => $_ENV['JWT_SECRET'] ?? '',
    'access_ttl' => (int) ($_ENV['JWT_ACCESS_TTL'] ?? 900),
    'refresh_ttl' => (int) ($_ENV['JWT_REFRESH_TTL'] ?? 2592000),
    'issuer' => $_ENV['JWT_ISSUER'] ?? 'api.mizapos.com',
    'algorithm' => 'HS256',
];
