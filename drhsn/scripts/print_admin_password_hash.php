<?php
declare(strict_types=1);

/**
 * طباعة هاش bcrypt لوضع ADMIN_PASSWORD_HASH في .env (انتقالي).
 *
 *   php scripts/print_admin_password_hash.php "your-password"
 */

$plain = (string) ($argv[1] ?? '');
if (strlen($plain) < 4) {
    fwrite(STDERR, "Usage: php scripts/print_admin_password_hash.php \"password\"\n");
    exit(1);
}

echo password_hash($plain, PASSWORD_BCRYPT, ['cost' => 10]) . "\n";
