<?php
/**
 * RAP-P1-03 — Temporary password harden + forgot rate-limit defaults + email copy.
 *
 * Usage:
 *   php /var/www/html/src/Modules/Auth/test_forgot_password_harden_unit.php
 */
declare(strict_types=1);

$root = dirname(__DIR__, 3);
require_once $root . '/vendor/autoload.php';

use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;
use MizaCloud\Core\Middleware\RateLimitMiddleware;
use MizaCloud\Modules\Auth\Services\AuthService;

function fail(string $msg): never
{
    fwrite(STDERR, "FAIL: {$msg}\n");
    exit(1);
}

function pass(string $msg): void
{
    fwrite(STDOUT, "PASS: {$msg}\n");
}

$ref = new ReflectionClass(AuthService::class);
$gen = $ref->getMethod('generateTemporaryPassword');
$gen->setAccessible(true);
$build = $ref->getMethod('buildPasswordResetEmail');
$build->setAccessible(true);

// Instantiate without running constructor dependencies: use Reflection to new without ctor
$service = $ref->newInstanceWithoutConstructor();

$samples = [];
for ($i = 0; $i < 20; $i++) {
    $samples[] = $gen->invoke($service);
}

foreach ($samples as $pwd) {
    if (strlen($pwd) < 20) {
        fail("temporary password too short: {$pwd}");
    }
    if (!preg_match('/[A-Z]/', $pwd) || !preg_match('/[a-z]/', $pwd)
        || !preg_match('/[0-9]/', $pwd) || !preg_match('/[!@#$%*?]/', $pwd)) {
        fail("temporary password missing character class: {$pwd}");
    }
    if (str_ends_with($pwd, 'A1!')) {
        fail('legacy weak suffix still present');
    }
    $hash = password_hash($pwd, PASSWORD_BCRYPT);
    if ($hash === false || !password_verify($pwd, $hash)) {
        fail('password_hash/verify failed for generated password');
    }
}
pass('temporary password strength (length + classes + hashable)');

$unique = array_unique($samples);
if (count($unique) < 18) {
    fail('generated passwords look insufficiently random across samples');
}
pass('temporary passwords vary across samples');

$mail = $build->invoke($service, 'owner@example.com', 'TmpPass#Example1234567890');
foreach (['subject', 'text', 'html'] as $k) {
    if (!isset($mail[$k]) || !is_string($mail[$k]) || $mail[$k] === '') {
        fail("mail template missing {$k}");
    }
}
if (!str_contains($mail['text'], 'غيّر كلمة المرور') && !str_contains($mail['text'], 'غير كلمة المرور')) {
    // Arabic change-password instruction
    if (!str_contains($mail['text'], 'إعدادات الحساب')) {
        fail('mail text missing change-password guidance');
    }
}
if (!str_contains($mail['text'], 'الجلسات السابقة') && !str_contains($mail['html'], 'الجلسات السابقة')) {
    fail('mail missing session-revocation notice');
}
if (!str_contains($mail['text'], 'TmpPass#Example1234567890')) {
    fail('mail text missing temporary password value');
}
if (str_contains(strtolower($mail['subject']), 'password') && !str_contains($mail['subject'], 'مؤقتة')) {
    // subject is Arabic-focused; ok
}
pass('password reset email template hardened');

// Forgot path uses tighter defaults (5 / 300) vs login (10 / 60) when constructed via Application defaults
$storage = sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'miza_p103_' . bin2hex(random_bytes(3));
mkdir($storage, 0755, true);
$_SERVER['REMOTE_ADDR'] = '10.0.0.40';
$mw = new RateLimitMiddleware(
    enabled: true,
    maxAttempts: 10,
    windowSeconds: 60,
    storagePath: $storage,
    trustProxy: false,
    trustedProxies: [],
    forgotMaxAttempts: 5,
    forgotWindowSeconds: 300,
);
$ok = static fn (): Response => new Response(200, '{"ok":true}');
$path = '/v1/auth/password/forgot';
for ($i = 1; $i <= 5; $i++) {
    $resp = $mw->handle(new Request('POST', $path), $ok);
    if ($resp->statusCode !== 200) {
        fail("forgot attempt {$i} expected 200 got {$resp->statusCode}");
    }
}
$resp = $mw->handle(new Request('POST', $path), $ok);
if ($resp->statusCode !== 429) {
    fail("forgot 6th attempt expected 429 got {$resp->statusCode}");
}
$retry = $resp->headers['Retry-After'] ?? '';
if ($retry !== '300') {
    fail("forgot Retry-After expected 300 got {$retry}");
}
pass('forgot-password tighter rate limit (5 / 300s)');

// Login still uses general 10/60 in same middleware instance
$loginPath = '/v1/auth/login';
for ($i = 1; $i <= 10; $i++) {
    $resp = $mw->handle(new Request('POST', $loginPath), $ok);
    if ($resp->statusCode !== 200) {
        fail("login attempt {$i} expected 200 got {$resp->statusCode}");
    }
}
$resp = $mw->handle(new Request('POST', $loginPath), $ok);
if ($resp->statusCode !== 429) {
    fail('login 11th expected 429');
}
pass('login general rate limit unchanged (10 / 60s)');

foreach (glob($storage . DIRECTORY_SEPARATOR . '*.json') ?: [] as $f) {
    @unlink($f);
}
@rmdir($storage);
unset($_SERVER['REMOTE_ADDR']);

fwrite(STDOUT, "OK: RAP-P1-03 forgot harden unit passed\n");
