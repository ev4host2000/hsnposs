<?php
/**
 * RAP-P1-02 — Platform admin token server-side revocation.
 *
 * Usage:
 *   docker compose -f cloud/docker-compose.test.yml exec -T api \
 *     php /var/www/html/src/Modules/Admin/test_platform_admin_token_unit.php
 *
 * Requires migration 020_platform_admin_tokens.sql applied.
 */
declare(strict_types=1);

$root = dirname(__DIR__, 3);
require_once $root . '/vendor/autoload.php';

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Database\Connection;
use MizaCloud\Modules\Admin\Support\PlatformAdminBearer;
use MizaCloud\Modules\Auth\Repositories\AuthRepository;
use MizaCloud\Modules\Auth\Services\JwtService;
use MizaCloud\Modules\Auth\Support\TokenHasher;

function fail(string $msg): never
{
    fwrite(STDERR, "FAIL: {$msg}\n");
    exit(1);
}

function pass(string $msg): void
{
    fwrite(STDOUT, "PASS: {$msg}\n");
}

function assertHttpException(callable $fn, int $expectedStatus, string $label): void
{
    try {
        $fn();
        fail("{$label}: expected HttpException {$expectedStatus}");
    } catch (HttpException $e) {
        if ($e->statusCode !== $expectedStatus) {
            fail("{$label}: expected status {$expectedStatus}, got {$e->statusCode} ({$e->getMessage()})");
        }
    }
}

function bearerRequest(string $token): Request
{
    return new Request('GET', '/v1/admin/me', ['Authorization' => 'Bearer ' . $token]);
}

function issueAndStore(
    JwtService $jwt,
    AuthRepository $auth,
    int $ttl = 3600,
): array {
    $scopes = ['platform:read', 'platform:write'];
    $issued = $jwt->issuePlatformAdminToken($scopes, $ttl);
    $expires = (new DateTimeImmutable('now'))->modify('+' . $ttl . ' seconds');
    if ($expires === false) {
        fail('failed to compute expiry');
    }
    $auth->createPlatformAdminToken(
        $issued['jti'],
        TokenHasher::hash($issued['token']),
        $scopes,
        $expires,
    );

    return $issued;
}

$dbName = getenv('DB_DATABASE') ?: (getenv('DB_NAME') ?: 'mizacloud');
$conn = new Connection([
    'host' => getenv('DB_HOST') ?: 'postgres',
    'port' => (int) (getenv('DB_PORT') ?: 5432),
    'database' => $dbName,
    'username' => getenv('DB_USERNAME') ?: (getenv('DB_USER') ?: 'mizacloud'),
    'password' => getenv('DB_PASSWORD') ?: '',
]);
$pdo = $conn->pdo();

$tableExists = $pdo->query(
    "SELECT to_regclass('public.platform_admin_tokens') IS NOT NULL",
)->fetchColumn();
if (!$tableExists) {
    fail('platform_admin_tokens table missing — apply 020_platform_admin_tokens.sql');
}

$jwtSecret = getenv('JWT_SECRET') ?: 'ci-test-jwt-secret-not-for-production';
$jwt = new JwtService($jwtSecret, 'api.mizapos.com', 900);
$auth = new AuthRepository($conn);
$bearer = new PlatformAdminBearer($jwt, $auth);

$tokenIds = [];

try {
    // T1 — Ops login storage: issued token has active DB row
    $loginIssued = issueAndStore($jwt, $auth);
    $tokenIds[] = $loginIssued['jti'];
    $st = $pdo->prepare('SELECT revoked_at IS NULL FROM platform_admin_tokens WHERE id = :id');
    $st->execute(['id' => $loginIssued['jti']]);
    if (!$st->fetchColumn()) {
        fail('T1 login: token row not active');
    }
    pass('T1 Ops login — token row stored and active');

    // T2 — Bearer accepts valid token (platform:read)
    $claims = $bearer->authenticate(bearerRequest($loginIssued['token']), ['platform:read']);
    if (($claims['token_type'] ?? '') !== 'platform_admin') {
        fail('T2: unexpected token_type');
    }
    pass('T2 Ops authenticate — valid JWT + DB row');

    // T2b — Regression: platform:write scope on protected path pattern
    $bearer->authenticate(bearerRequest($loginIssued['token']), ['platform:write']);
    pass('T2b Admin regression — platform:write scope accepted');

    // T3 — Ops logout revokes server-side
    $auth->revokePlatformAdminTokenByHash(TokenHasher::hash($loginIssued['token']));
    $st->execute(['id' => $loginIssued['jti']]);
    if ($st->fetchColumn()) {
        fail('T3 logout: revoked_at should be set');
    }
    pass('T3 Ops logout — token revoked in DB');

    // T4 — JWT after logout returns 401
    assertHttpException(
        static fn () => $bearer->authenticate(bearerRequest($loginIssued['token']), ['platform:read']),
        401,
        'T4 post-logout',
    );
    pass('T4 JWT after logout — 401 Access token revoked');

    // T5 — New login after logout works
    $secondIssued = issueAndStore($jwt, $auth);
    $tokenIds[] = $secondIssued['jti'];
    $bearer->authenticate(bearerRequest($secondIssued['token']), ['platform:read']);
    pass('T5 new login after logout — bearer accepts new token');

    // T6 — JWT without DB row rejected
    $orphan = $jwt->issuePlatformAdminToken(['platform:read', 'platform:write'], 3600);
    assertHttpException(
        static fn () => $bearer->authenticate(bearerRequest($orphan['token']), ['platform:read']),
        401,
        'T6 orphan JWT',
    );
    pass('T6 revoked/orphan token — JWT without DB row returns 401');

    // T7 — New login revokes previous sessions (revokeAllActive policy)
    $thirdIssued = issueAndStore($jwt, $auth);
    $tokenIds[] = $thirdIssued['jti'];
    $auth->revokeAllActivePlatformAdminTokens();
    $fourthIssued = issueAndStore($jwt, $auth);
    $tokenIds[] = $fourthIssued['jti'];
    assertHttpException(
        static fn () => $bearer->authenticate(bearerRequest($thirdIssued['token']), ['platform:read']),
        401,
        'T7 prior session',
    );
    $bearer->authenticate(bearerRequest($fourthIssued['token']), ['platform:read']);
    pass('T7 login revokes prior sessions — old token 401, new token OK');

    // T8 — Regression: listCompanies-style read + write scopes still enforced
    assertHttpException(
        static fn () => $bearer->authenticate(bearerRequest($fourthIssued['token']), ['platform:admin']),
        403,
        'T8 insufficient scope',
    );
    pass('T8 Admin regression — insufficient scope returns 403');

    fwrite(STDOUT, "\nALL P1-02 PLATFORM ADMIN TOKEN TESTS PASSED\n");
} finally {
    if ($tokenIds !== []) {
        $in = implode(',', array_fill(0, count($tokenIds), '?'));
        $pdo->prepare("DELETE FROM platform_admin_tokens WHERE id IN ($in)")->execute($tokenIds);
    }
}
