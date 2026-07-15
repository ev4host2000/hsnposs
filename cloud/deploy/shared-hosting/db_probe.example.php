<?php
/**
 * Miza Cloud — PostgreSQL connectivity probe (EXAMPLE ONLY).
 *
 * NEVER commit a real copy with secrets.
 * 1. Copy to db_probe.php (gitignored)
 * 2. Fill placeholders or export env vars below
 * 3. Upload temporarily to a non-public path if needed
 * 4. Delete immediately after use
 *
 * Usage:
 *   MIZA_DB_PROBE_KEY=... MIZA_DB_PASSWORD=... php db_probe.php
 *   or open once with ?key=... then delete the file.
 */
declare(strict_types=1);

$expectedKey = getenv('MIZA_DB_PROBE_KEY') ?: 'CHANGE_ME_PROBE_KEY';
if ($expectedKey === 'CHANGE_ME_PROBE_KEY' || ($_GET['key'] ?? '') !== $expectedKey) {
    http_response_code(404);
    exit('Not found');
}

header('Content-Type: text/plain; charset=utf-8');

$config = [
    'host'     => getenv('MIZA_DB_HOST') ?: 'localhost',
    'port'     => getenv('MIZA_DB_PORT') ?: '5432',
    'dbname'   => getenv('MIZA_DB_NAME') ?: 'CHANGE_ME_DB',
    'user'     => getenv('MIZA_DB_USER') ?: 'CHANGE_ME_USER',
    'password' => getenv('MIZA_DB_PASSWORD') ?: 'CHANGE_ME_PASSWORD',
];

if (
    $config['dbname'] === 'CHANGE_ME_DB'
    || $config['user'] === 'CHANGE_ME_USER'
    || $config['password'] === 'CHANGE_ME_PASSWORD'
) {
    exit("FAIL: Set MIZA_DB_* environment variables before running.\n");
}

echo "=== Miza Cloud DB Probe ===\n\n";

if (!extension_loaded('pgsql') && !extension_loaded('pdo_pgsql')) {
    exit("FAIL: PHP extensions pgsql / pdo_pgsql not loaded.\n");
}
echo 'OK: PHP ' . PHP_VERSION . "\n";
echo 'OK: ' . (extension_loaded('pdo_pgsql') ? 'pdo_pgsql' : 'pgsql') . " loaded\n\n";

$dsn = sprintf(
    'pgsql:host=%s;port=%s;dbname=%s',
    $config['host'],
    $config['port'],
    $config['dbname'],
);

try {
    $pdo = new PDO($dsn, $config['user'], $config['password'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);
} catch (Throwable $e) {
    exit('FAIL: Connection — ' . $e->getMessage() . "\n");
}
echo "OK: Connected to database\n\n";

$version = $pdo->query('SELECT version()')->fetchColumn();
echo "PostgreSQL version:\n$version\n\n";

echo "=== Done — delete this file now ===\n";
