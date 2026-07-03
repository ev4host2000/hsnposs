<?php
declare(strict_types=1);

/**
 * Cron script: send expiry notifications.
 *
 * Usage (cPanel cron):
 *   /usr/bin/php -d detect_unicode=0 /home/USER/public_html/drhsn/scripts/send_expiry_notifications.php
 *
 * Notes:
 * - Reads NOTIFY_* from .env/env like the web app.
 * - Uses PHP mail() (hosting must be configured).
 * - Prevents duplicates via notification_log unique index.
 */

require __DIR__ . '/../includes/config.php';
require __DIR__ . '/../includes/db.php';
require __DIR__ . '/../includes/jwt.php';
require __DIR__ . '/../includes/handlers.php';

$config = activation_config();

try {
    $pdo = activation_open_db($config['DATABASE_PATH']);
} catch (Throwable $e) {
    fwrite(STDERR, "[fatal] SQLite: {$e->getMessage()}\n");
    exit(1);
}

// System actor (not an admin login)
$actor = ['email' => 'cron', 'acl' => 'approver', 'role' => 'admin', 'sub' => 'cron'];

$out = activation_run_expiry_notifications($pdo, $config, $actor);

echo json_encode(['ok' => true] + $out, JSON_UNESCAPED_UNICODE) . "\n";

