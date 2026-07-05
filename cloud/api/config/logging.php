<?php

declare(strict_types=1);

return [
    'level' => $_ENV['LOG_LEVEL'] ?? 'info',
    'path' => $_ENV['LOG_PATH'] ?? 'storage/logs',
];
