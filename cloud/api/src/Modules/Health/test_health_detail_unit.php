<?php
/**
 * RAP-P1-06 — Public health redaction + operator X-Health-Token detail.
 *
 * Usage:
 *   php /var/www/html/src/Modules/Health/test_health_detail_unit.php
 */
declare(strict_types=1);

$root = dirname(__DIR__, 3);
require_once $root . '/vendor/autoload.php';

use MizaCloud\Core\Config\Config;
use MizaCloud\Core\Database\Connection;
use MizaCloud\Core\Database\DatabaseManager;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Modules\Health\Repositories\HealthRepository;
use MizaCloud\Modules\Health\Services\HealthService;

function fail(string $msg): never
{
    fwrite(STDERR, "FAIL: {$msg}\n");
    exit(1);
}

function pass(string $msg): void
{
    fwrite(STDOUT, "PASS: {$msg}\n");
}

/** @param array<string, mixed> $appOverlay */
function withAppOverlay(Config $config, array $appOverlay): Config
{
    $ref = new ReflectionClass($config);
    $prop = $ref->getProperty('items');
    $prop->setAccessible(true);
    /** @var array<string, array<string, mixed>> $items */
    $items = $prop->getValue($config);
    $app = is_array($items['app'] ?? null) ? $items['app'] : [];
    $items['app'] = array_merge($app, $appOverlay);
    $prop->setValue($config, $items);

    return $config;
}

$config = Config::loadFromPath($root . '/config');
$dbName = getenv('DB_DATABASE') ?: (getenv('DB_NAME') ?: 'mizacloud');
$conn = new Connection([
    'host' => getenv('DB_HOST') ?: 'postgres',
    'port' => (int) (getenv('DB_PORT') ?: 5432),
    'database' => $dbName,
    'username' => getenv('DB_USERNAME') ?: (getenv('DB_USER') ?: 'mizacloud'),
    'password' => getenv('DB_PASSWORD') ?: '',
]);
$repo = new HealthRepository(new DatabaseManager($conn));

$logPath = sys_get_temp_dir() . '/miza_health_p106_' . bin2hex(random_bytes(3));
@mkdir($logPath, 0755, true);
$logger = new Logger($logPath, 'error');

$token = 'p1-06-test-token-' . bin2hex(random_bytes(4));
$config = withAppOverlay($config, ['health_detail_token' => $token]);
$service = new HealthService($repo, $config, $logger);

$publicReq = new Request('GET', '/v1/health', []);
if ($service->isDetailAuthorized($publicReq)) {
    fail('public request must not be detail-authorized');
}
pass('public request not detail-authorized');

$versionPublic = $service->version(false);
if (isset($versionPublic['php_version']) || isset($versionPublic['environment'])) {
    fail('public version leaked php_version/environment');
}
if (!isset($versionPublic['name'], $versionPublic['api_version'])) {
    fail('public version missing name/api_version');
}
pass('public version redacted');

$dbPublic = $service->database(false);
if (array_key_exists('latency_ms', $dbPublic) || array_key_exists('server_time', $dbPublic) || array_key_exists('error', $dbPublic)) {
    fail('public database leaked detail fields');
}
if (!array_key_exists('connected', $dbPublic)) {
    fail('public database missing connected');
}
pass('public database redacted');

$summaryPublic = $service->summary(false);
if (isset($summaryPublic['version']['php_version']) || isset($summaryPublic['version']['environment'])) {
    fail('public summary version leaked sensitive fields');
}
if (isset($summaryPublic['checks']['database']['latency_ms'])) {
    fail('public summary leaked database latency');
}
if (($summaryPublic['status'] ?? '') === '') {
    fail('public summary missing status');
}
pass('public summary redacted');

$detailReq = new Request('GET', '/v1/health', ['X-Health-Token' => $token]);
if (!$service->isDetailAuthorized($detailReq)) {
    fail('operator token should authorize detail');
}
$versionDetail = $service->version(true);
if (!isset($versionDetail['php_version'], $versionDetail['environment'])) {
    fail('detailed version missing operator fields');
}
$dbDetail = $service->database(true);
if (!array_key_exists('latency_ms', $dbDetail) || !array_key_exists('server_time', $dbDetail)) {
    fail('detailed database missing operator fields');
}
$summaryDetail = $service->summary(true);
if (!isset($summaryDetail['version']['php_version'], $summaryDetail['checks']['database']['latency_ms'])) {
    fail('detailed summary missing operator fields');
}
pass('operator detail authorized with X-Health-Token');

$badReq = new Request('GET', '/v1/health', ['X-Health-Token' => 'wrong-token']);
if ($service->isDetailAuthorized($badReq)) {
    fail('wrong token must not authorize detail');
}
pass('wrong token rejected');

$config = withAppOverlay($config, ['health_detail_token' => '']);
$serviceNoToken = new HealthService($repo, $config, $logger);
if ($serviceNoToken->isDetailAuthorized($detailReq)) {
    fail('empty HEALTH_DETAIL_TOKEN must deny detail');
}
pass('empty token config denies detail');

fwrite(STDOUT, "OK: RAP-P1-06 health detail unit passed\n");
