<?php

declare(strict_types=1);

return [
    'access_ttl' => (int) ($_ENV['OWNER_PORTAL_ACCESS_TTL'] ?? 28800),
];
