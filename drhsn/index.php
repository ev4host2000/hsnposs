<?php
declare(strict_types=1);

require __DIR__ . '/includes/config.php';
require __DIR__ . '/includes/db.php';
require __DIR__ . '/includes/jwt.php';
require __DIR__ . '/includes/handlers.php';

$config = activation_config();

try {
    $pdo = activation_open_db($config['DATABASE_PATH']);
} catch (Throwable $e) {
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo '[fatal] SQLite: ' . $e->getMessage() . "\nDATABASE_PATH=" . $config['DATABASE_PATH'];
    exit(1);
}

$method = strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET'));

$pathInfo = $_SERVER['PATH_INFO'] ?? null;
if (
    is_string($pathInfo)
    && $pathInfo !== ''
    && $pathInfo !== '/'
    && preg_match('#^/(api|admin)(/|$)#', $pathInfo)
) {
    $path = $pathInfo[0] === '/' ? $pathInfo : '/' . $pathInfo;
} else {
    $uri = (string) (parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH) ?? '/');
    $base = (string) $config['APP_BASE_PATH'];
    if ($base !== '' && strncmp($uri, $base, strlen($base)) === 0) {
        $path = substr($uri, strlen($base)) ?: '/';
    } else {
        $path = $uri;
    }
    // cPanel / Apache: /drhsn/index.php/admin/... بعد إزالة القاعدة يبقى /index.php/admin/...
    if (preg_match('#^/index\.php(?:$|(/.*)$)#i', $path, $m)) {
        $path = (isset($m[1]) && $m[1] !== '') ? $m[1] : '/';
    }
}
if ($path === '') {
    $path = '/';
}
if ($path[0] !== '/') {
    $path = '/' . $path;
}

activation_dispatch($pdo, $config, $method, $path);
