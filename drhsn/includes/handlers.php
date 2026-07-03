<?php
declare(strict_types=1);

require_once __DIR__ . '/signup_email.php';
require_once __DIR__ . '/distributor_license.php';
require_once __DIR__ . '/field_orders.php';
require_once __DIR__ . '/field_expenses.php';
require_once __DIR__ . '/field_returns.php';
require_once __DIR__ . '/field_catalog.php';
require_once __DIR__ . '/field_truck_stock.php';
require_once __DIR__ . '/team_users.php';

function activation_now_iso(): string
{
    return (new DateTimeImmutable('now', new DateTimeZone('UTC')))->format('Y-m-d\TH:i:s.v\Z');
}

/** @return array{id:string,title:string,message:string,createdAt:string}|null */
function activation_broadcast_notice_for_client(PDO $pdo, string $installationId): ?array
{
    return null;
}

function activation_cors_headers(): array
{
    return [
        'Access-Control-Allow-Origin' => '*',
        'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers' => 'Authorization, Content-Type, X-Installation-Secret',
    ];
}

/** @return never */
function activation_send(int $code, array $headers, string $body = ''): void
{
    http_response_code($code);
    foreach ($headers as $k => $v) {
        header($k . ': ' . $v, true);
    }
    echo $body;
    exit;
}

/** @return never */
function activation_redirect(string $location): void
{
    activation_send(302, [
        'Location' => $location,
        'Cache-Control' => 'no-store, no-cache, must-revalidate',
        'Pragma' => 'no-cache',
    ], '');
}

/** @return never */
function activation_json(int $code, array $body): void
{
    activation_send(
        $code,
        array_merge(activation_cors_headers(), ['Content-Type' => 'application/json; charset=utf-8']),
        (string) json_encode($body, JSON_UNESCAPED_UNICODE),
    );
}

function activation_json_body(): array
{
    $raw = file_get_contents('php://input');
    if ($raw === false || $raw === '') {
        return [];
    }
    $j = json_decode($raw, true);
    return is_array($j) ? $j : [];
}

function activation_clear_redeems_for_signup(PDO $pdo, string $signupRequestId): void
{
    $st = $pdo->prepare('DELETE FROM activation_redeems WHERE signup_request_id = ?');
    $st->execute([$signupRequestId]);
}

/**
 * يطابق أحدث صف في تفاصيل المشترك (requested_at DESC).
 *
 * @return array{used:int,max:int,signupRequestId:?string}
 */
function activation_redeem_slot_stats(PDO $pdo, string $organizationId, string $emailNormalized): array
{
    $st = $pdo->prepare(
        "SELECT id FROM signup_requests
         WHERE trim(organization_id) = trim(?) AND lower(trim(email)) = ?
         ORDER BY requested_at DESC
         LIMIT 1",
    );
    $st->execute([$organizationId, $emailNormalized]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return ['used' => 0, 'max' => 2, 'signupRequestId' => null];
    }
    $sid = (string) $row['id'];
    $c = $pdo->prepare('SELECT COUNT(*) AS n FROM activation_redeems WHERE signup_request_id = ?');
    $c->execute([$sid]);
    $n = (int) ($c->fetch(PDO::FETCH_ASSOC)['n'] ?? 0);

    return ['used' => $n, 'max' => 2, 'signupRequestId' => $sid];
}

function activation_bearer_token(): ?string
{
    $auth = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    if ($auth !== '' && preg_match('/Bearer\s+(.+)/i', $auth, $m)) {
        return trim($m[1]);
    }
    if (function_exists('apache_request_headers')) {
        foreach (apache_request_headers() ?: [] as $k => $v) {
            if (strtolower((string) $k) === 'authorization' && preg_match('/Bearer\s+(.+)/i', (string) $v, $m)) {
                return trim($m[1]);
            }
        }
    }
    return null;
}

function activation_jwt_secret(array $config): string
{
    $s = (string) $config['JWT_SECRET'];
    return $s !== '' ? $s : 'unsafe-dev-secret';
}

function activation_norm_activation_code(string $raw): string
{
    return strtoupper((string) preg_replace('/\s+/', '', trim($raw)));
}

/** Crockford-like base32 (32 chars) — يطابق توليد كود الجهاز في تطبيق MizaPos. */
function activation_device_link_alphabet(): string
{
    return '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
}

function activation_uuid_to_device_link_code(string $uuid): string
{
    $hex = strtolower(str_replace('-', '', trim($uuid)));
    if (strlen($hex) !== 32 || !ctype_xdigit($hex)) {
        return '';
    }
    $bytes = hex2bin($hex);
    if ($bytes === false || strlen($bytes) !== 16) {
        return '';
    }
    $alpha = activation_device_link_alphabet();
    $out = '';
    $buffer = 0;
    $bits = 0;
    for ($i = 0; $i < 16; $i++) {
        $buffer = ($buffer << 8) | ord($bytes[$i]);
        $bits += 8;
        while ($bits >= 5) {
            $bits -= 5;
            $out .= $alpha[($buffer >> $bits) & 31];
        }
    }
    if ($bits > 0) {
        $out .= $alpha[($buffer << (5 - $bits)) & 31];
    }
    while (strlen($out) < 26) {
        $out .= '2';
    }
    $out = substr($out, 0, 26);

    return sprintf(
        'MPZ-%s-%s-%s-%s-%s-%s',
        substr($out, 0, 4),
        substr($out, 4, 4),
        substr($out, 8, 4),
        substr($out, 12, 4),
        substr($out, 16, 4),
        substr($out, 20, 6),
    );
}

/** @return non-empty-string|null UUID v4 */
function activation_device_link_code_to_installation_id(string $raw): ?string
{
    $t = strtoupper(preg_replace('/[^2-9A-Z]+/', '', trim($raw)));
    if (str_starts_with($t, 'MPZ')) {
        $t = substr($t, 3);
    }
    if (strlen($t) < 26) {
        return null;
    }
    $t = substr($t, 0, 26);
    $alpha = activation_device_link_alphabet();
    $map = [];
    for ($i = 0; $i < strlen($alpha); $i++) {
        $map[$alpha[$i]] = $i;
    }
    $bits = 0;
    $buffer = 0;
    $bytes = '';
    for ($i = 0; $i < strlen($t); $i++) {
        $c = $t[$i];
        if (!isset($map[$c])) {
            return null;
        }
        $buffer = ($buffer << 5) | $map[$c];
        $bits += 5;
        if ($bits >= 8) {
            $bits -= 8;
            $bytes .= chr(($buffer >> $bits) & 0xff);
        }
    }
    if (strlen($bytes) !== 16) {
        return null;
    }
    $hex = bin2hex($bytes);

    return sprintf(
        '%s-%s-%s-%s-%s',
        substr($hex, 0, 8),
        substr($hex, 8, 4),
        substr($hex, 12, 4),
        substr($hex, 16, 4),
        substr($hex, 20, 12),
    );
}

/**
 * إكمال ربط جهاز بتفعيل معتمد (حدّ جهازين لكل اشتراك).
 *
 * @param array<string,mixed> $matched صف من signup_requests
 *
 * @return array{0:int,1:array<string,mixed>}
 */
function activation_redeem_for_installation(PDO $pdo, array $matched, string $installationId): array
{
    if (strlen(trim($installationId)) < 8) {
        return [400, ['error' => 'validation']];
    }
    $installationId = trim($installationId);
    $signupRequestId = (string) $matched['id'];
    $dup = $pdo->prepare(
        'SELECT 1 FROM activation_redeems WHERE signup_request_id = ? AND installation_id = ?',
    );
    $dup->execute([$signupRequestId, $installationId]);
    if ($dup->fetch(PDO::FETCH_ASSOC)) {
        return [
            200,
            [
                'signupRequestId' => $signupRequestId,
                'organizationId' => $matched['organization_id'],
                'email' => $matched['email'],
                'fullName' => $matched['full_name'],
                'phone' => $matched['phone'],
                'dialCode' => $matched['dial_code'],
                'passwordHash' => $matched['password_hash'],
                'devicesRedeemed' => null,
                'devicesRedeemMax' => 2,
            ],
        ];
    }
    $cntSt = $pdo->prepare('SELECT COUNT(*) AS n FROM activation_redeems WHERE signup_request_id = ?');
    $cntSt->execute([$signupRequestId]);
    $n = (int) ($cntSt->fetch(PDO::FETCH_ASSOC)['n'] ?? 0);
    if ($n >= 2) {
        return [403, ['error' => 'too_many_devices']];
    }
    $now = activation_now_iso();
    $ins = $pdo->prepare(
        'INSERT INTO activation_redeems (signup_request_id, installation_id, redeemed_at) VALUES (?, ?, ?)',
    );
    $ins->execute([$signupRequestId, $installationId, $now]);
    $after = $n + 1;
    if ($after >= 2) {
        $clr = $pdo->prepare('UPDATE signup_requests SET issued_activation_key = NULL WHERE id = ?');
        $clr->execute([$signupRequestId]);
    }

    return [
        200,
        [
            'signupRequestId' => $signupRequestId,
            'organizationId' => $matched['organization_id'],
            'email' => $matched['email'],
            'fullName' => $matched['full_name'],
            'phone' => $matched['phone'],
            'dialCode' => $matched['dial_code'],
            'passwordHash' => $matched['password_hash'],
            'devicesRedeemed' => $after,
            'devicesRedeemMax' => 2,
        ],
    ];
}

/**
 * صفوف طلبات التسجيل التي تطابق البريد وكلمة المرور (أي حالة).
 *
 * @return list<array<string,mixed>>
 */
function activation_signup_rows_matching_password(
    PDO $pdo,
    string $emailNorm,
    string $password,
    string $organizationId,
): array {
    if ($organizationId !== '') {
        $st = $pdo->prepare(
            'SELECT * FROM signup_requests
             WHERE trim(organization_id) = trim(?) AND lower(trim(email)) = ?
             ORDER BY requested_at DESC',
        );
        $st->execute([$organizationId, $emailNorm]);
        $rows = $st->fetchAll(PDO::FETCH_ASSOC);
    } else {
        $st = $pdo->prepare(
            'SELECT * FROM signup_requests
             WHERE lower(trim(email)) = ?
             ORDER BY requested_at DESC',
        );
        $st->execute([$emailNorm]);
        $rows = $st->fetchAll(PDO::FETCH_ASSOC);
    }
    $out = [];
    foreach ($rows as $r) {
        $hash = (string) ($r['password_hash'] ?? '');
        if ($hash !== '' && password_verify($password, $hash)) {
            $out[] = $r;
        }
    }

    return $out;
}

/**
 * يختار طلباً معتمداً لربط الجهاز، أو يُرجع سبب الرفض (معلّق / مرفوض / تعدد مؤسسات).
 *
 * @param list<array<string,mixed>> $passwordMatches
 *
 * @return array{row:?array<string,mixed>, error?:string, organizationIds?:list<string>}
 */
function activation_pick_approved_signup_for_device_link(array $passwordMatches): array
{
    if (count($passwordMatches) === 0) {
        return ['row' => null];
    }
    $approved = [];
    $pending = [];
    $rejected = [];
    foreach ($passwordMatches as $r) {
        $s = (string) ($r['status'] ?? '');
        if ($s === 'approved') {
            $approved[] = $r;
        } elseif ($s === 'pending') {
            $pending[] = $r;
        } elseif ($s === 'rejected') {
            $rejected[] = $r;
        }
    }
    if (count($approved) === 0) {
        if (count($pending) > 0) {
            return ['row' => null, 'error' => 'signup_not_approved'];
        }
        if (count($rejected) > 0) {
            return ['row' => null, 'error' => 'signup_rejected'];
        }

        return ['row' => null];
    }
    if (count($approved) > 1) {
        $orgs = [];
        foreach ($approved as $r) {
            $o = trim((string) ($r['organization_id'] ?? ''));
            if ($o !== '') {
                $orgs[] = $o;
            }
        }
        $orgs = array_values(array_unique($orgs));

        return ['row' => null, 'error' => 'ambiguous', 'organizationIds' => $orgs];
    }

    return ['row' => $approved[0]];
}

/**
 * يحلّ كود الجهاز إلى المشترك المعتمد المرتبط بآخر استرداد لهذا الجهاز.
 *
 * @return array{ok:bool,error?:string,installationId?:string,signup?:array<string,mixed>}
 */
function activation_resolve_signup_from_device_code(PDO $pdo, string $deviceLinkCode): array
{
    $installationId = activation_device_link_code_to_installation_id($deviceLinkCode);
    if ($installationId === null) {
        return ['ok' => false, 'error' => 'invalid_device_code'];
    }
    $st = $pdo->prepare(
        "SELECT sr.* FROM activation_redeems ar
         INNER JOIN signup_requests sr ON sr.id = ar.signup_request_id
         WHERE ar.installation_id = ?
           AND sr.status = 'approved'
         ORDER BY ar.redeemed_at DESC
         LIMIT 1",
    );
    $st->execute([$installationId]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return [
            'ok' => false,
            'error' => 'not_found',
            'installationId' => $installationId,
        ];
    }

    return [
        'ok' => true,
        'installationId' => $installationId,
        'signup' => $row,
    ];
}

/**
 * حلّ كود الجهاز من آخر claim محفوظ من محاولة دخول/تفعيل المشترك.
 *
 * @return array{ok:bool,error?:string,installationId?:string,organizationId?:string,email?:string,signupRequestId?:string|null}
 */
function activation_resolve_claim_from_device_code(PDO $pdo, string $deviceLinkCode): array
{
    $installationId = activation_device_link_code_to_installation_id($deviceLinkCode);
    if ($installationId === null) {
        return ['ok' => false, 'error' => 'invalid_device_code'];
    }
    $st = $pdo->prepare(
        'SELECT organization_id, email_normalized
         FROM device_link_claims
         WHERE installation_id = ?
         LIMIT 1',
    );
    $st->execute([$installationId]);
    $claim = $st->fetch(PDO::FETCH_ASSOC);
    if (!$claim) {
        return ['ok' => false, 'error' => 'not_found', 'installationId' => $installationId];
    }
    $org = trim((string) ($claim['organization_id'] ?? ''));
    $email = strtolower(trim((string) ($claim['email_normalized'] ?? '')));
    if ($org === '' || strpos($email, '@') === false) {
        return ['ok' => false, 'error' => 'not_found', 'installationId' => $installationId];
    }
    $stSu = $pdo->prepare(
        "SELECT id FROM signup_requests
         WHERE trim(organization_id) = trim(?)
           AND lower(trim(email)) = ?
           AND status = 'approved'
         ORDER BY COALESCE(reviewed_at, requested_at) DESC
         LIMIT 1",
    );
    $stSu->execute([$org, $email]);
    $sr = $stSu->fetch(PDO::FETCH_ASSOC);
    return [
        'ok' => true,
        'installationId' => $installationId,
        'organizationId' => $org,
        'email' => $email,
        'signupRequestId' => $sr ? (string) ($sr['id'] ?? '') : null,
    ];
}

/**
 * عند وصول claim من البرنامج بعد تفعيل الجهاز مسبقاً:
 * حدّث البريد على سجلات الاشتراك/الأجهزة ليظهر فوراً في لوحة الويب.
 */
function activation_apply_claim_email_to_activated_records(
    PDO $pdo,
    string $installationId,
    string $organizationId,
    string $email,
): void {
    $installationId = trim($installationId);
    $organizationId = trim($organizationId);
    $email = strtolower(trim($email));
    if ($installationId === '' || $organizationId === '' || strpos($email, '@') === false) {
        return;
    }
    $stDevice = $pdo->prepare(
        "SELECT email_normalized FROM subscriber_devices
         WHERE installation_id = ? AND trim(organization_id) = trim(?)
         ORDER BY CASE WHEN revoked_at IS NULL THEN 0 ELSE 1 END, last_seen_at DESC, created_at DESC
         LIMIT 1",
    );
    $stDevice->execute([$installationId, $organizationId]);
    $row = $stDevice->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return;
    }
    $fromEmail = strtolower(trim((string) ($row['email_normalized'] ?? '')));
    if ($fromEmail === '' || $fromEmail === $email) {
        return;
    }

    $upLs = $pdo->prepare(
        'UPDATE license_snapshots
         SET email_normalized = ?
         WHERE trim(organization_id) = trim(?) AND email_normalized = ?',
    );
    $upLs->execute([$email, $organizationId, $fromEmail]);

    $upSd = $pdo->prepare(
        'UPDATE subscriber_devices
         SET email_normalized = ?
         WHERE trim(organization_id) = trim(?) AND email_normalized = ?',
    );
    $upSd->execute([$email, $organizationId, $fromEmail]);

    $upLog = $pdo->prepare(
        'UPDATE subscriber_activity_log
         SET email_normalized = ?
         WHERE trim(organization_id) = trim(?) AND email_normalized = ?',
    );
    $upLog->execute([$email, $organizationId, $fromEmail]);

    $upSr = $pdo->prepare(
        'UPDATE signup_requests
         SET email = ?
         WHERE trim(organization_id) = trim(?) AND lower(trim(email)) = ? AND status = ?',
    );
    $upSr->execute([$email, $organizationId, $fromEmail, 'approved']);
}

/** توحيد رمز الاتصال الدولي (+970 …) لعرض العلم والدولة. */
function activation_normalize_dial_code(string $dial): string
{
    $d = preg_replace('/\s+/', '', trim($dial)) ?? '';
    if ($d === '') {
        return '';
    }
    if ($d[0] !== '+') {
        if (str_starts_with($d, '00')) {
            $d = '+' . substr($d, 2);
        } else {
            $d = '+' . ltrim($d, '0');
        }
    }
    return $d;
}

/** عدد الأيام الكاملة المتبقية (سالب بعد الانتهاء) حتى نهاية التاريخ بصيغة ISO. */
function activation_days_remaining(?string $isoUtc): ?int
{
    if ($isoUtc === null) {
        return null;
    }
    $t = trim((string) $isoUtc);
    if ($t === '') {
        return null;
    }
    $endTs = strtotime($t);
    if ($endTs === false) {
        return null;
    }

    return (int) floor(($endTs - time()) / 86400);
}

/** ترحيل أعمدة signup_requests الاختيارية (عند نشر handlers دون db.php محدّث). */
function activation_ensure_signup_schema(PDO $pdo): void
{
    static $done = false;
    if ($done) {
        return;
    }
    $srCols = $pdo->query('PRAGMA table_info(signup_requests)')->fetchAll(PDO::FETCH_ASSOC);
    $srNames = [];
    foreach ($srCols as $c) {
        $srNames[$c['name']] = true;
    }
    if (!isset($srNames['email_verified'])) {
        $pdo->exec('ALTER TABLE signup_requests ADD COLUMN email_verified INTEGER NOT NULL DEFAULT 0');
        $pdo->exec("UPDATE signup_requests SET email_verified = 1 WHERE status = 'approved'");
    }
    if (!isset($srNames['email_verify_token'])) {
        $pdo->exec('ALTER TABLE signup_requests ADD COLUMN email_verify_token TEXT');
    }
    if (!isset($srNames['email_verify_expires_at'])) {
        $pdo->exec('ALTER TABLE signup_requests ADD COLUMN email_verify_expires_at TEXT');
    }
    if (!isset($srNames['email_welcome_sent_at'])) {
        $pdo->exec('ALTER TABLE signup_requests ADD COLUMN email_welcome_sent_at TEXT');
    }
    $done = true;
}

/**
 * يُضيف لكل صف مسجّل: هل مرتبط بقسيمة؟ وأي كود/حالة.
 * @param array<int,array<string,mixed>> $items
 */
function activation_enrich_signups_voucher_links(PDO $pdo, array &$items): void
{
    if ($items === []) {
        return;
    }
    $conds = [];
    $params = [];
    foreach ($items as $row) {
        $em = strtolower(trim((string) ($row['email'] ?? '')));
        $org = trim((string) ($row['organization_id'] ?? ''));
        if ($em === '' || strpos($em, '@') === false) {
            continue;
        }
        $conds[] = '(lower(trim(redeemed_by_email)) = ? AND trim(redeemed_by_organization_id) = trim(?))';
        $params[] = $em;
        $params[] = $org;
    }
    $byKey = [];
    if ($conds !== []) {
        $sql = 'SELECT code, status, lower(trim(redeemed_by_email)) AS em,
                       trim(redeemed_by_organization_id) AS org, first_redeemed_at
                FROM vouchers WHERE ' . implode(' OR ', $conds);
        $st = $pdo->prepare($sql);
        $st->execute($params);
        foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $v) {
            $key = (string) $v['em'] . "\0" . (string) $v['org'];
            if (!isset($byKey[$key])) {
                $byKey[$key] = [];
            }
            $byKey[$key][] = $v;
        }
    }
    foreach ($items as &$row) {
        $em = strtolower(trim((string) ($row['email'] ?? '')));
        $org = trim((string) ($row['organization_id'] ?? ''));
        $key = $em . "\0" . $org;
        $list = $byKey[$key] ?? [];
        if ($list === []) {
            $row['has_voucher'] = false;
            $row['voucher_code'] = null;
            $row['voucher_status'] = null;
            $row['voucher_count'] = 0;
            continue;
        }
        usort($list, static function (array $a, array $b): int {
            $prio = static function (string $s): int {
                if ($s === 'redeemed') {
                    return 0;
                }
                if ($s === 'revoked') {
                    return 1;
                }
                return 2;
            };
            $pa = $prio((string) ($a['status'] ?? ''));
            $pb = $prio((string) ($b['status'] ?? ''));
            if ($pa !== $pb) {
                return $pa <=> $pb;
            }
            return strcmp((string) ($b['first_redeemed_at'] ?? ''), (string) ($a['first_redeemed_at'] ?? ''));
        });
        $primary = $list[0];
        $row['has_voucher'] = true;
        $row['voucher_code'] = (string) ($primary['code'] ?? '');
        $row['voucher_status'] = (string) ($primary['status'] ?? '');
        $row['voucher_count'] = count($list);
    }
    unset($row);
}

/** أحدث تاريخين بصيغة ISO (UTC) أو null. */
function activation_latest_iso_date(?string $a, ?string $b): ?string
{
    $ta = ($a !== null && trim($a) !== '') ? strtotime(trim($a)) : false;
    $tb = ($b !== null && trim($b) !== '') ? strtotime(trim($b)) : false;
    if ($ta === false && $tb === false) {
        return null;
    }
    if ($ta === false) {
        return trim((string) $b);
    }
    if ($tb === false) {
        return trim((string) $a);
    }

    return $ta >= $tb ? trim((string) $a) : trim((string) $b);
}

/** @return array<string,mixed>|null */
function activation_require_admin(array $config, PDO $pdo): ?array
{
    $token = activation_bearer_token();
    if ($token === null || $token === '') {
        activation_json(401, ['error' => 'unauthorized']);
    }
    $payload = activation_jwt_verify($token, activation_jwt_secret($config));
    if ($payload === null) {
        activation_json(401, ['error' => 'unauthorized']);
    }
    if (($payload['role'] ?? '') !== 'admin') {
        activation_json(403, ['error' => 'forbidden']);
    }
    $acl = $payload['acl'] ?? 'approver';
    if ($acl !== 'viewer' && $acl !== 'approver') {
        $acl = 'approver';
    }
    $payload['acl'] = $acl;
    $payload['adminRole'] = (string) ($payload['adminRole'] ?? ($acl === 'viewer' ? 'viewer' : 'admin'));
    return $payload;
}

function activation_admin_role(array $admin): string
{
    $r = strtolower(trim((string) ($admin['adminRole'] ?? 'admin')));
    if (!in_array($r, ['admin', 'billing', 'support', 'viewer'], true)) {
        $r = (($admin['acl'] ?? '') === 'viewer') ? 'viewer' : 'admin';
    }
    return $r;
}

function activation_require_perm(array $admin, string $perm): void
{
    $role = activation_admin_role($admin);
    $allowed = [
        'viewer' => ['read'],
        'support' => ['read', 'freeze', 'unfreeze', 'approve_reject'],
        'billing' => ['read', 'extend', 'freeze', 'unfreeze', 'notifications'],
        'admin' => ['read', 'extend', 'freeze', 'unfreeze', 'approve_reject', 'delete', 'notifications', 'password'],
    ];
    $list = $allowed[$role] ?? ['read'];
    if ($perm === 'read') {
        return;
    }
    if (!in_array($perm, $list, true)) {
        activation_json(403, ['error' => 'forbidden']);
    }
}

function activation_admin_reviewer_label(array $admin): string
{
    $em = trim((string) ($admin['email'] ?? ''));
    if ($em !== '') {
        return $em;
    }
    return (string) ($admin['sub'] ?? 'admin');
}

function activation_log_subscriber_event(
    PDO $pdo,
    string $organizationId,
    string $emailNormalized,
    array $admin,
    string $eventType,
    array $details = []
): void {
    try {
        $ins = $pdo->prepare(
            'INSERT INTO subscriber_activity_log (
                id, organization_id, email_normalized, actor_email, event_type, details_json, created_at
             ) VALUES (?, ?, ?, ?, ?, ?, ?)',
        );
        $ins->execute([
            activation_uuid(),
            trim($organizationId),
            strtolower(trim($emailNormalized)),
            trim((string) ($admin['email'] ?? '')),
            trim($eventType),
            (string) json_encode($details, JSON_UNESCAPED_UNICODE),
            activation_now_iso(),
        ]);
    } catch (Throwable $e) {
        error_log('[activation] subscriber-activity-log: ' . $e->getMessage());
    }
}

/** @return array{installationId:string,computerName:string,osUser:string,osName:string,emailSlug:string,fingerprint:string}|null */
function activation_parse_device_binding(string $raw): ?array
{
    $t = trim($raw);
    if ($t === '') {
        return null;
    }
    $parts = explode('|', $t);
    if (count($parts) < 5) {
        return null;
    }
    $installationId = trim($parts[0]);
    if (strlen($installationId) < 8) {
        return null;
    }
    $computerName = trim($parts[1] ?? '');
    $osUser = trim($parts[2] ?? '');
    $osName = trim($parts[3] ?? '');
    $emailSlug = trim($parts[4] ?? '');
    return [
        'installationId' => $installationId,
        'computerName' => $computerName,
        'osUser' => $osUser,
        'osName' => $osName,
        'emailSlug' => $emailSlug,
        'fingerprint' => $t,
    ];
}

function activation_parse_notify_days(array $config): array
{
    $raw = (string) ($config['NOTIFY_DAYS'] ?? '7,3,1,0');
    $parts = preg_split('/\s*,\s*/', trim($raw)) ?: [];
    $out = [];
    foreach ($parts as $p) {
        if ($p === '') {
            continue;
        }
        $n = (int) $p;
        if ($n < 0) {
            continue;
        }
        $out[$n] = true;
    }
    $days = array_keys($out);
    sort($days);
    return $days;
}

function activation_notify_subject(array $config, int $days, string $organizationId): string
{
    $t = trim((string) ($config['NOTIFY_SUBJECT'] ?? 'تنبيه: اشتراك MizaPos على وشك الانتهاء'));
    if ($t === '') {
        $t = 'تنبيه: اشتراك MizaPos على وشك الانتهاء';
    }
    return str_replace(['{days}', '{organizationId}'], [(string) $days, $organizationId], $t);
}

function activation_notify_body_html(array $config, string $fullName, string $organizationId, string $email, int $days, ?string $effectiveUntil): string
{
    $h = static function (string $s): string {
        return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    };
    $name = $fullName !== '' ? $fullName : $email;
    $untilLine = $effectiveUntil ? ('<li><strong>تاريخ الانتهاء:</strong> ' . $h($effectiveUntil) . '</li>') : '';
    $daysLine = $days === 0 ? 'اليوم' : ('بعد ' . $days . ' يوم');

    $renewTpl = trim((string) ($config['NOTIFY_RENEW_URL_TEMPLATE'] ?? ''));
    $renewUrl = '';
    if ($renewTpl !== '') {
        $renewUrl = str_replace(
            ['{organizationId}', '{email}'],
            [rawurlencode($organizationId), rawurlencode($email)],
            $renewTpl,
        );
    }
    $wa = trim((string) ($config['NOTIFY_SUPPORT_WHATSAPP'] ?? ''));
    $actions = '';
    if ($renewUrl !== '' || $wa !== '') {
        $actions .= '<div style="margin:14px 0 0;display:flex;gap:10px;flex-wrap:wrap">';
        if ($renewUrl !== '') {
            $actions .= '<a href="' . $h($renewUrl) . '" style="background:#2563eb;color:#fff;text-decoration:none;padding:10px 14px;border-radius:10px;font-weight:700">تجديد الاشتراك</a>';
        }
        if ($wa !== '') {
            $actions .= '<a href="' . $h($wa) . '" style="background:#16a34a;color:#fff;text-decoration:none;padding:10px 14px;border-radius:10px;font-weight:700">واتساب الدعم</a>';
        }
        $actions .= '</div>';
    }

    return '<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8"/>'
        . '<body style="font-family:Segoe UI,Tahoma,Arial,sans-serif;line-height:1.7;background:#f8fafc;padding:18px">'
        . '<div style="max-width:640px;margin:0 auto;background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:18px">'
        . '<h2 style="margin:0 0 10px;font-size:18px">تنبيه انتهاء اشتراك MizaPos</h2>'
        . '<p style="margin:0 0 10px">مرحباً ' . $h($name) . '،</p>'
        . '<p style="margin:0 0 10px">اشتراككم على مؤسسة <strong>' . $h($organizationId) . '</strong> سينتهي ' . $h($daysLine) . '.</p>'
        . '<ul style="margin:0 0 12px;padding:0 18px">'
        . $untilLine
        . '<li><strong>البريد:</strong> ' . $h($email) . '</li>'
        . '</ul>'
        . '<p style="margin:0">للتجديد أو المساعدة، يرجى التواصل مع الدعم.</p>'
        . $actions
        . '<p style="margin:14px 0 0;color:#64748b;font-size:12px">تم إرسال هذا التنبيه تلقائياً.</p>'
        . '</div></body></html>';
}

function activation_whatsapp_enabled(array $config): bool
{
    $v = strtolower(trim((string) ($config['WA_NOTIFY_ENABLED'] ?? '0')));
    return in_array($v, ['1', 'true', 'yes', 'on'], true);
}

/** @return array{ok:bool,error?:string,status?:int} */
function activation_send_whatsapp(array $config, string $organizationId, string $email, int $days, ?string $effectiveUntil): array
{
    if (!activation_whatsapp_enabled($config)) {
        return ['ok' => false, 'error' => 'disabled'];
    }
    $url = trim((string) ($config['WA_NOTIFY_WEBHOOK_URL'] ?? ''));
    if ($url === '') {
        return ['ok' => false, 'error' => 'webhook_not_configured'];
    }
    $payload = [
        'organizationId' => $organizationId,
        'email' => $email,
        'daysRemaining' => $days,
        'effectiveUntil' => $effectiveUntil,
        'message' => ($days === 0 ? 'تنبيه: اشتراكك ينتهي اليوم' : ('تنبيه: اشتراكك ينتهي بعد ' . $days . ' يوم')),
    ];
    $headers = "Content-Type: application/json\r\n";
    $tok = trim((string) ($config['WA_NOTIFY_TOKEN'] ?? ''));
    if ($tok !== '') {
        $headers .= 'Authorization: Bearer ' . $tok . "\r\n";
    }
    $ctx = stream_context_create([
        'http' => [
            'method' => 'POST',
            'header' => $headers,
            'content' => (string) json_encode($payload, JSON_UNESCAPED_UNICODE),
            'timeout' => 12,
            'ignore_errors' => true,
        ],
    ]);
    $resp = @file_get_contents($url, false, $ctx);
    $status = 0;
    if (isset($http_response_header[0]) && preg_match('/\s(\d{3})\s/', (string) $http_response_header[0], $m)) {
        $status = (int) $m[1];
    }
    if ($resp === false || $status < 200 || $status >= 300) {
        return ['ok' => false, 'error' => 'webhook_failed', 'status' => $status];
    }
    return ['ok' => true, 'status' => $status];
}

/** @return array<string,mixed> */
function activation_build_notification_preview(PDO $pdo, array $config, string $organizationId, string $email, int $days): array
{
    $org = trim($organizationId);
    $em = strtolower(trim($email));
    if ($org === '' || strpos($em, '@') === false || $days < 0) {
        return ['error' => 'validation'];
    }
    $stSu = $pdo->prepare(
        "SELECT full_name
         FROM signup_requests
         WHERE trim(organization_id) = trim(?) AND lower(trim(email)) = ?
         ORDER BY requested_at DESC
         LIMIT 1",
    );
    $stSu->execute([$org, $em]);
    $fullName = trim((string) ($stSu->fetch(PDO::FETCH_ASSOC)['full_name'] ?? ''));

    $stLic = $pdo->prepare(
        'SELECT subscription_annual_until, admin_valid_until, access_suspended
         FROM license_snapshots
         WHERE trim(organization_id) = trim(?) AND email_normalized = ?
         LIMIT 1',
    );
    $stLic->execute([$org, $em]);
    $lic = $stLic->fetch(PDO::FETCH_ASSOC) ?: null;

    $effectiveUntil = null;
    $suspended = false;
    if ($lic) {
        $suspended = !empty($lic['access_suspended']);
        if (!$suspended) {
            $effectiveUntil = activation_latest_iso_date(
                isset($lic['admin_valid_until']) ? (string) $lic['admin_valid_until'] : null,
                isset($lic['subscription_annual_until']) ? (string) $lic['subscription_annual_until'] : null,
            );
        }
    }

    $subject = activation_notify_subject($config, $days, $org);
    $html = activation_notify_body_html($config, $fullName, $org, $em, $days, $effectiveUntil);

    return [
        'ok' => true,
        'to' => $em,
        'supportCc' => (string) ($config['NOTIFY_SUPPORT_CC'] ?? ''),
        'supportBcc' => (string) ($config['NOTIFY_SUPPORT_BCC'] ?? ''),
        'dryRun' => activation_mail_dry_run($config),
        'enabled' => activation_mail_enabled($config),
        'organizationId' => $org,
        'days' => $days,
        'effectiveUntil' => $effectiveUntil,
        'accessSuspended' => $suspended,
        'subject' => $subject,
        'html' => $html,
    ];
}

/** @return array{scanned:int,sent:int,skipped:int,failed:int,details:array<int,array<string,mixed>>} */
function activation_run_expiry_notifications(PDO $pdo, array $config, array $adminPayload): array
{
    require_once __DIR__ . '/mailer.php';
    $daysList = activation_parse_notify_days($config);
    if ($daysList === []) {
        return ['scanned' => 0, 'sent' => 0, 'skipped' => 0, 'failed' => 0, 'details' => []];
    }

    $st = $pdo->query(
        "SELECT
            ls.organization_id AS organization_id,
            ls.email_normalized AS email_normalized,
            ls.subscription_annual_until AS subscription_annual_until,
            ls.admin_valid_until AS admin_valid_until,
            ls.access_suspended AS access_suspended,
            COALESCE(sr.full_name, '') AS full_name
         FROM license_snapshots ls
         LEFT JOIN signup_requests sr
           ON trim(sr.organization_id) = trim(ls.organization_id)
          AND lower(trim(sr.email)) = ls.email_normalized
         GROUP BY ls.organization_id, ls.email_normalized",
    );
    $rows = $st->fetchAll(PDO::FETCH_ASSOC);

    $scanned = 0;
    $sent = 0;
    $skipped = 0;
    $failed = 0;
    $details = [];

    foreach ($rows as $r) {
        $scanned++;
        $org = trim((string) ($r['organization_id'] ?? ''));
        $email = strtolower(trim((string) ($r['email_normalized'] ?? '')));
        $fullName = trim((string) ($r['full_name'] ?? ''));
        $suspended = !empty($r['access_suspended']);
        if ($org === '' || $email === '' || $suspended) {
            $skipped++;
            continue;
        }

        $eff = activation_latest_iso_date(
            isset($r['admin_valid_until']) ? (string) $r['admin_valid_until'] : null,
            isset($r['subscription_annual_until']) ? (string) $r['subscription_annual_until'] : null,
        );
        $daysRemaining = activation_days_remaining($eff);
        if ($daysRemaining === null || !in_array($daysRemaining, $daysList, true)) {
            continue;
        }

        $kind = 'expiry_' . $daysRemaining . 'd';
        $chk = $pdo->prepare(
            'SELECT 1 FROM notification_log WHERE organization_id = ? AND email_normalized = ? AND kind = ? LIMIT 1',
        );
        $chk->execute([$org, $email, $kind]);
        if ($chk->fetchColumn()) {
            $skipped++;
            continue;
        }

        $subject = activation_notify_subject($config, $daysRemaining, $org);
        $body = activation_notify_body_html($config, $fullName, $org, $email, $daysRemaining, $eff);
        $res = activation_send_email($config, $email, $subject, $body);
        $wa = activation_send_whatsapp($config, $org, $email, $daysRemaining, $eff);
        $ok = !empty($res['ok']);

        $ins = $pdo->prepare(
            'INSERT INTO notification_log (id, organization_id, email_normalized, kind, status, details_json, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?)',
        );
        $status = $ok ? (!empty($res['dryRun']) ? 'dry_run' : 'sent') : 'failed';
        $ins->execute([
            activation_uuid(),
            $org,
            $email,
            $kind,
            $status,
            (string) json_encode([
                'daysRemaining' => $daysRemaining,
                'effectiveUntil' => $eff,
                'actorEmail' => (string) ($adminPayload['email'] ?? ''),
                'mail' => $res,
                'whatsapp' => $wa,
            ], JSON_UNESCAPED_UNICODE),
            activation_now_iso(),
        ]);

        if ($ok) {
            $sent++;
            activation_log_subscriber_event($pdo, $org, $email, $adminPayload, 'expiry_notification_sent', [
                'kind' => $kind,
                'daysRemaining' => $daysRemaining,
                'effectiveUntil' => $eff,
                'dryRun' => !empty($res['dryRun']),
                'whatsapp' => $wa,
            ]);
        } else {
            $failed++;
        }

        $details[] = [
            'organizationId' => $org,
            'email' => $email,
            'daysRemaining' => $daysRemaining,
            'status' => $status,
        ];
    }

    return compact('scanned', 'sent', 'skipped', 'failed', 'details');
}

/** @return array{ok:bool, error?:string, adminValidUntil?:string|null} */
function activation_apply_license_action(PDO $pdo, array $admin, string $organizationId, string $email, string $action, array $body): array
{
    $organizationId = trim($organizationId);
    $email = strtolower(trim($email));
    $action = trim($action);
    if ($organizationId === '' || strpos($email, '@') === false || $action === '') {
        return ['ok' => false, 'error' => 'validation'];
    }
    $now = activation_now_iso();

    $ensureRow = function () use ($pdo, $organizationId, $email, $now): void {
        $st = $pdo->prepare(
            'SELECT 1 FROM license_snapshots WHERE organization_id = ? AND email_normalized = ?',
        );
        $st->execute([$organizationId, $email]);
        if (!$st->fetchColumn()) {
            $ins = $pdo->prepare(
                'INSERT INTO license_snapshots (
                    organization_id, email_normalized, trial_end_at, subscription_annual_until, legacy_activated, updated_at, admin_valid_until, access_suspended
                ) VALUES (?, ?, NULL, NULL, 0, ?, NULL, 0)',
            );
            $ins->execute([$organizationId, $email, $now]);
        }
    };

    try {
        if ($action === 'freeze') {
            $ensureRow();
            $pdo->prepare(
                'UPDATE license_snapshots SET access_suspended = 1, updated_at = ? WHERE organization_id = ? AND email_normalized = ?',
            )->execute([$now, $organizationId, $email]);
            activation_log_subscriber_event($pdo, $organizationId, $email, $admin, 'license_freeze', []);
            return ['ok' => true];
        }
        if ($action === 'unfreeze') {
            $ensureRow();
            $pdo->prepare(
                'UPDATE license_snapshots SET access_suspended = 0, updated_at = ? WHERE organization_id = ? AND email_normalized = ?',
            )->execute([$now, $organizationId, $email]);
            activation_log_subscriber_event($pdo, $organizationId, $email, $admin, 'license_unfreeze', []);
            return ['ok' => true];
        }
        if ($action === 'delete_snapshot') {
            $pdo->beginTransaction();
            $st = $pdo->prepare(
                'DELETE FROM license_snapshots WHERE organization_id = ? AND email_normalized = ?',
            );
            $st->execute([$organizationId, $email]);
            $nSnap = $st->rowCount();
            $st2 = $pdo->prepare(
                'DELETE FROM signup_requests WHERE organization_id = ? AND lower(trim(email)) = ?',
            );
            $st2->execute([$organizationId, $email]);
            $nSign = $st2->rowCount();
            activation_log_subscriber_event($pdo, $organizationId, $email, $admin, 'subscriber_deleted', [
                'deletedSnapshots' => $nSnap,
                'deletedSignups' => $nSign,
            ]);
            $pdo->commit();
            return ['ok' => true];
        }
        if (
            $action === 'extend_subscription'
            || $action === 'renew_subscription'
            || $action === 'set_subscription_until'
        ) {
            $days = (int) ($body['days'] ?? 0);
            if ($action === 'renew_subscription' && $days < 1) {
                $days = 365;
            }
            if ($action === 'extend_subscription' && $days < 1) {
                return ['ok' => false, 'error' => 'validation'];
            }
            $ensureRow();
            if ($action === 'set_subscription_until') {
                $untilRaw = trim((string) ($body['until'] ?? ''));
                if ($untilRaw === '' || strtotime($untilRaw) === false) {
                    return ['ok' => false, 'error' => 'validation'];
                }
                $newUntil = gmdate('Y-m-d\TH:i:s\Z', strtotime($untilRaw));
            } else {
                if ($days < 1 || $days > 3660) {
                    return ['ok' => false, 'error' => 'validation'];
                }
                $st = $pdo->prepare(
                    'SELECT subscription_annual_until, admin_valid_until FROM license_snapshots
                     WHERE organization_id = ? AND email_normalized = ?',
                );
                $st->execute([$organizationId, $email]);
                $lic = $st->fetch(PDO::FETCH_ASSOC) ?: [];
                $current = activation_latest_iso_date(
                    isset($lic['admin_valid_until']) ? (string) $lic['admin_valid_until'] : null,
                    isset($lic['subscription_annual_until']) ? (string) $lic['subscription_annual_until'] : null,
                );
                $baseTs = time();
                if ($current !== null && strtotime($current) !== false && strtotime($current) > $baseTs) {
                    $baseTs = strtotime($current);
                }
                $newUntil = gmdate('Y-m-d\TH:i:s\Z', $baseTs + ($days * 86400));
            }
            $pdo->prepare(
                'UPDATE license_snapshots SET admin_valid_until = ?, updated_at = ? WHERE organization_id = ? AND email_normalized = ?',
            )->execute([$newUntil, $now, $organizationId, $email]);
            activation_log_subscriber_event($pdo, $organizationId, $email, $admin, $action, [
                'days' => $days > 0 ? $days : null,
                'until' => $newUntil,
            ]);
            return ['ok' => true, 'adminValidUntil' => $newUntil];
        }
        return ['ok' => false, 'error' => 'unknown_action'];
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        error_log('[activation] license-action: ' . $e->getMessage());
        return ['ok' => false, 'error' => 'server'];
    }
}

function activation_require_shared_secret(array $config): void
{
    $sec = (string) $config['REMOTE_SIGNUP_SHARED_SECRET'];
    if ($sec === '') {
        return;
    }
    $h = (string) ($_SERVER['HTTP_X_INSTALLATION_SECRET'] ?? '');
    if ($h !== $sec) {
        activation_json(403, ['error' => 'forbidden']);
    }
}

/** @return string|null bcrypt hash */
function activation_resolve_signup_password_hash(array $body): ?string
{
    $hashIn = trim((string) ($body['passwordHash'] ?? ''));
    if (preg_match('/^\$(2a|2b|2y)\$/', $hashIn)) {
        return $hashIn;
    }
    $password = (string) ($body['password'] ?? '');
    if (strlen($password) >= 4) {
        return password_hash($password, PASSWORD_BCRYPT, ['cost' => 10]);
    }
    return null;
}

/* ============================ Vouchers helpers ============================ */

/** أبجدية القسيمة: بلا 0/O 1/I B/8 لتقليل أخطاء النسخ اليدوي. */
function activation_voucher_alphabet(): string
{
    return 'ACDEFHJKLMNPQRTUVWXY23479';
}

/** يولّد كوداً بصيغة Miza-XXXX-XXXX-XXXX. */
function activation_voucher_generate_code(): string
{
    $alpha = activation_voucher_alphabet();
    $len = strlen($alpha);
    $parts = [];
    for ($g = 0; $g < 3; $g++) {
        $s = '';
        for ($i = 0; $i < 4; $i++) {
            $s .= $alpha[random_int(0, $len - 1)];
        }
        $parts[] = $s;
    }
    return 'Miza-' . implode('-', $parts);
}

/**
 * يطبّع كود القسيمة: trim/upper-letters حسب الأبجدية + بادئة Miza- ثابتة.
 * يقبل بادئات شائعة (miza/MIZA/HSN قديم) ويعيد البادئة Miza- القانونية.
 */
function activation_voucher_normalize(string $raw): string
{
    $s = strtoupper(trim($raw));
    $s = (string) preg_replace('/\s+/', '', $s);
    $s = (string) preg_replace('/^MIZA[-_]?/', '', $s);
    $s = (string) preg_replace('/^HSN[-_]?/', '', $s);
    $s = (string) preg_replace('/[^A-Z0-9]/', '', $s);
    if (strlen($s) !== 12) {
        return '';
    }
    $alpha = activation_voucher_alphabet();
    for ($i = 0; $i < 12; $i++) {
        if (strpos($alpha, $s[$i]) === false) {
            return '';
        }
    }
    return 'Miza-' . substr($s, 0, 4) . '-' . substr($s, 4, 4) . '-' . substr($s, 8, 4);
}

/** توحيد installation_id لتفادي تعداد الجهاز مرتين بسبب اختلاف حالة الأحرف. */
function activation_normalize_installation_id(string $installationId): string
{
    return strtolower(trim($installationId));
}

/**
 * يُلغى تفعيل الصفوف المكررة لنفس الجهاز على القسيمة (نفس المعرّف بعد التوحيد
 * أو نفس بصمة الجهاز)، مع الإبقاء على الصف النشط الأحدث — دون حذف السجلات.
 */
function activation_voucher_dedupe_redemptions(PDO $pdo, string $voucherCode): int
{
    $st = $pdo->prepare(
        'SELECT installation_id, device_fingerprint, revoked_at, last_seen_at, redeemed_at
         FROM voucher_redemptions
         WHERE voucher_code = ?
         ORDER BY
           CASE WHEN revoked_at IS NULL THEN 0 ELSE 1 END,
           COALESCE(last_seen_at, redeemed_at) DESC',
    );
    $st->execute([$voucherCode]);
    $rows = $st->fetchAll(PDO::FETCH_ASSOC);
    $keepIds = [];
    $keepFps = [];
    $revoked = 0;
    $now = activation_now_iso();
    foreach ($rows as $row) {
        $rawId = (string) ($row['installation_id'] ?? '');
        $iid = activation_normalize_installation_id($rawId);
        if ($iid === '') {
            continue;
        }
        $fp = trim((string) ($row['device_fingerprint'] ?? ''));
        $isDup = isset($keepIds[$iid]) || ($fp !== '' && isset($keepFps[$fp]));
        if ($isDup && empty($row['revoked_at'])) {
            $up = $pdo->prepare(
                'UPDATE voucher_redemptions SET revoked_at = ?
                 WHERE voucher_code = ? AND installation_id = ? AND revoked_at IS NULL',
            );
            $up->execute([$now, $voucherCode, $rawId]);
            $revoked += $up->rowCount();
            continue;
        }
        if (empty($row['revoked_at'])) {
            $keepIds[$iid] = true;
            if ($fp !== '') {
                $keepFps[$fp] = true;
            }
        }
    }
    return $revoked;
}

/** عدد الأجهزة الفعلية النشطة (بدون تكرار لنفس الجهاز). */
function activation_voucher_active_device_count(PDO $pdo, string $voucherCode): int
{
    activation_voucher_dedupe_redemptions($pdo, $voucherCode);
    $st = $pdo->prepare(
        "SELECT COUNT(DISTINCT lower(trim(installation_id))) AS n
         FROM voucher_redemptions
         WHERE voucher_code = ? AND revoked_at IS NULL",
    );
    $st->execute([$voucherCode]);
    return (int) ($st->fetch(PDO::FETCH_ASSOC)['n'] ?? 0);
}

/** desktop | android — من الحقل أو من os_name للسجلات القديمة. */
function activation_normalize_device_platform(string $raw, string $osName = ''): string
{
    $p = strtolower(trim($raw));
    if (in_array($p, ['desktop', 'windows', 'linux', 'macos', 'win'], true)) {
        return 'desktop';
    }
    if (in_array($p, ['android', 'mobile'], true)) {
        return 'android';
    }
    $os = strtolower(trim($osName));
    if ($os !== '' && str_contains($os, 'android')) {
        return 'android';
    }
    if (in_array($os, ['windows', 'linux', 'macos'], true)) {
        return 'desktop';
    }
    return 'desktop';
}

/** هل تُطبَّق حدود منفصلة لحاسوب/أندرويد (قسائم جديدة فقط)؟ */
function activation_voucher_uses_typed_limits(array $v): bool
{
    return array_key_exists('max_desktop_devices', $v)
        && array_key_exists('max_android_devices', $v)
        && $v['max_desktop_devices'] !== null
        && $v['max_android_devices'] !== null;
}

function activation_redemption_platform(array $row): string
{
    $stored = trim((string) ($row['device_platform'] ?? ''));
    if ($stored !== '') {
        return activation_normalize_device_platform($stored);
    }
    return activation_normalize_device_platform('', (string) ($row['os_name'] ?? ''));
}

function activation_voucher_active_count_by_platform(PDO $pdo, string $voucherCode, string $platform): int
{
    activation_voucher_dedupe_redemptions($pdo, $voucherCode);
    $st = $pdo->prepare(
        'SELECT device_platform, os_name FROM voucher_redemptions
         WHERE voucher_code = ? AND revoked_at IS NULL',
    );
    $st->execute([$voucherCode]);
    $n = 0;
    foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $row) {
        if (activation_redemption_platform($row) === $platform) {
            $n++;
        }
    }
    return $n;
}

/**
 * @return array<string,mixed>|null خطأ JSON أو null إن سُمح بالتفعيل
 */
function activation_voucher_device_slot_error(
    PDO $pdo,
    array $v,
    string $code,
    string $platform,
    bool $isNewActivation,
): ?array {
    if (!$isNewActivation) {
        return null;
    }
    if (activation_voucher_uses_typed_limits($v)) {
        $maxDesktop = max(0, (int) $v['max_desktop_devices']);
        $maxAndroid = max(0, (int) $v['max_android_devices']);
        $usedDesktop = activation_voucher_active_count_by_platform($pdo, $code, 'desktop');
        $usedAndroid = activation_voucher_active_count_by_platform($pdo, $code, 'android');
        if ($platform === 'desktop' && $usedDesktop >= $maxDesktop) {
            return [
                'error' => 'desktop_limit_reached',
                'maxDesktop' => $maxDesktop,
                'usedDesktop' => $usedDesktop,
                'maxAndroid' => $maxAndroid,
                'usedAndroid' => $usedAndroid,
            ];
        }
        if ($platform === 'android' && $usedAndroid >= $maxAndroid) {
            return [
                'error' => 'android_limit_reached',
                'maxAndroid' => $maxAndroid,
                'usedAndroid' => $usedAndroid,
                'maxDesktop' => $maxDesktop,
                'usedDesktop' => $usedDesktop,
            ];
        }
        $usedTotal = activation_voucher_active_device_count($pdo, $code);
        $maxTotal = max(1, (int) $v['max_devices']);
        if ($usedTotal >= $maxTotal) {
            return ['error' => 'devices_limit_reached', 'max' => $maxTotal];
        }
        return null;
    }
    $used = activation_voucher_active_device_count($pdo, $code);
    if ($used >= (int) $v['max_devices']) {
        return ['error' => 'devices_limit_reached', 'max' => (int) $v['max_devices']];
    }
    return null;
}

function activation_voucher_platform_stats(PDO $pdo, string $code): array
{
    return [
        'usedDesktopDevices' => activation_voucher_active_count_by_platform($pdo, $code, 'desktop'),
        'usedAndroidDevices' => activation_voucher_active_count_by_platform($pdo, $code, 'android'),
    ];
}

function activation_voucher_public_fields(PDO $pdo, array $v, string $code): array
{
    $platformStats = activation_voucher_platform_stats($pdo, $code);
    $typed = activation_voucher_uses_typed_limits($v);
    return [
        'maxDevices' => (int) $v['max_devices'],
        'useTypedDeviceLimits' => $typed,
        'maxDesktopDevices' => $typed ? (int) $v['max_desktop_devices'] : null,
        'maxAndroidDevices' => $typed ? (int) $v['max_android_devices'] : null,
        'usedDesktopDevices' => $platformStats['usedDesktopDevices'],
        'usedAndroidDevices' => $platformStats['usedAndroidDevices'],
    ];
}

/**
 * سجل دخول/استرداد قسيمة لمشترك (للوحة المسؤول).
 * @return array{vouchers: list<array>, entries: list<array>, dedupedRows: int}
 */
function activation_subscriber_voucher_activity(PDO $pdo, string $organizationId, string $email): array
{
    $email = strtolower(trim($email));
    $organizationId = trim($organizationId);
    $st = $pdo->prepare(
        "SELECT code, status, max_devices, first_redeemed_at, revoked_at, revoke_reason
         FROM vouchers
         WHERE lower(trim(redeemed_by_email)) = ?
           AND trim(redeemed_by_organization_id) = trim(?)
         ORDER BY COALESCE(first_redeemed_at, created_at) DESC",
    );
    $st->execute([$email, $organizationId]);
    $vouchers = [];
    $entries = [];
    $dedupedTotal = 0;
    foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $v) {
        $code = (string) ($v['code'] ?? '');
        if ($code === '') {
            continue;
        }
        $dedupedTotal += activation_voucher_dedupe_redemptions($pdo, $code);
        $active = activation_voucher_active_device_count($pdo, $code);
        $vouchers[] = [
            'code' => $code,
            'status' => (string) ($v['status'] ?? ''),
            'maxDevices' => (int) ($v['max_devices'] ?? 0),
            'activeDevices' => $active,
            'firstRedeemedAt' => (string) ($v['first_redeemed_at'] ?? ''),
            'revokedAt' => (string) ($v['revoked_at'] ?? ''),
            'revokeReason' => (string) ($v['revoke_reason'] ?? ''),
        ];
        $dev = $pdo->prepare(
            'SELECT installation_id, device_fingerprint, computer_name, os_name, os_user,
                    redeemed_at, last_seen_at, revoked_at
             FROM voucher_redemptions
             WHERE voucher_code = ?
             ORDER BY redeemed_at DESC',
        );
        $dev->execute([$code]);
        foreach ($dev->fetchAll(PDO::FETCH_ASSOC) as $d) {
            $entries[] = [
                'voucherCode' => $code,
                'installationId' => (string) ($d['installation_id'] ?? ''),
                'deviceFingerprint' => (string) ($d['device_fingerprint'] ?? ''),
                'computerName' => (string) ($d['computer_name'] ?? ''),
                'osName' => (string) ($d['os_name'] ?? ''),
                'osUser' => (string) ($d['os_user'] ?? ''),
                'redeemedAt' => (string) ($d['redeemed_at'] ?? ''),
                'lastSeenAt' => (string) ($d['last_seen_at'] ?? ''),
                'revokedAt' => (string) ($d['revoked_at'] ?? ''),
                'isActive' => empty($d['revoked_at']),
            ];
        }
    }
    usort($entries, static function (array $a, array $b): int {
        return strcmp((string) ($b['redeemedAt'] ?? ''), (string) ($a['redeemedAt'] ?? ''));
    });
    return [
        'vouchers' => $vouchers,
        'entries' => $entries,
        'dedupedRows' => $dedupedTotal,
    ];
}

/** المشترك: يتحقق من JWT بـ role=subscriber ويُرجع payload. */
function activation_require_subscriber(array $config, PDO $pdo): array
{
    $token = activation_bearer_token();
    if ($token === null || $token === '') {
        activation_json(401, ['error' => 'unauthorized']);
    }
    $payload = activation_jwt_verify($token, activation_jwt_secret($config));
    if ($payload === null) {
        activation_json(401, ['error' => 'unauthorized']);
    }
    if (($payload['role'] ?? '') !== 'subscriber') {
        activation_json(403, ['error' => 'forbidden']);
    }
    $sid = (string) ($payload['sub'] ?? '');
    if ($sid === '') {
        activation_json(401, ['error' => 'unauthorized']);
    }
    $st = $pdo->prepare(
        'SELECT id, organization_id, email, full_name, phone, dial_code, status
         FROM signup_requests WHERE id = ? LIMIT 1',
    );
    $st->execute([$sid]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        activation_json(401, ['error' => 'unauthorized']);
    }
    return [
        'signup_request_id' => (string) $row['id'],
        'organization_id' => (string) $row['organization_id'],
        'email' => strtolower(trim((string) $row['email'])),
        'full_name' => (string) $row['full_name'],
        'phone' => (string) ($row['phone'] ?? ''),
        'dial_code' => (string) ($row['dial_code'] ?? ''),
        'status' => (string) $row['status'],
    ];
}

/**
 * يبني صف تفاصيل قسيمة (دون التفاصيل الحساسة للأجهزة) للوحة admin.
 * @return array<string,mixed>
 */
function activation_voucher_row_with_stats(PDO $pdo, array $v): array
{
    $code = (string) $v['code'];
    $used = activation_voucher_active_device_count($pdo, $code);

    // إثراء بسيط برمز هاتف المشترك (dial_code) لعرض علم الدولة في الواجهة.
    // (lookup خفيف من signup_requests؛ لا يُؤخّر القائمة لحجم الصفحة العادي).
    $dialCode = '';
    $email = trim((string) ($v['redeemed_by_email'] ?? ''));
    if ($email !== '') {
        $orgId = trim((string) ($v['redeemed_by_organization_id'] ?? ''));
        if ($orgId !== '') {
            $sub = $pdo->prepare(
                'SELECT dial_code FROM signup_requests
                 WHERE lower(trim(email)) = ? AND trim(organization_id) = trim(?)
                 ORDER BY requested_at DESC LIMIT 1',
            );
            $sub->execute([strtolower($email), $orgId]);
        } else {
            $sub = $pdo->prepare(
                'SELECT dial_code FROM signup_requests
                 WHERE lower(trim(email)) = ?
                 ORDER BY requested_at DESC LIMIT 1',
            );
            $sub->execute([strtolower($email)]);
        }
        $r = $sub->fetch(PDO::FETCH_ASSOC);
        if ($r) {
            $dialCode = activation_normalize_dial_code((string) ($r['dial_code'] ?? ''));
        }
    }

    return array_merge([
        'code' => $code,
        'usedDevices' => $used,
        'status' => (string) $v['status'],
        'batchId' => (string) ($v['batch_id'] ?? ''),
        'note' => (string) ($v['note'] ?? ''),
        'createdAt' => (string) ($v['created_at'] ?? ''),
        'createdBy' => (string) ($v['created_by_admin'] ?? ''),
        'firstRedeemedAt' => (string) ($v['first_redeemed_at'] ?? ''),
        'redeemedByEmail' => (string) ($v['redeemed_by_email'] ?? ''),
        'redeemedByOrganizationId' => (string) ($v['redeemed_by_organization_id'] ?? ''),
        'subscriberDialCode' => $dialCode,
        'revokedAt' => (string) ($v['revoked_at'] ?? ''),
        'revokedBy' => (string) ($v['revoked_by_admin'] ?? ''),
        'revokeReason' => (string) ($v['revoke_reason'] ?? ''),
        'usedDistributorSeats' => ($orgId = trim((string) ($v['redeemed_by_organization_id'] ?? ''))) !== ''
            ? distributor_license_count_distributor_seats($pdo, $orgId)
            : 0,
    ], activation_voucher_public_fields($pdo, $v, $code), distributor_license_voucher_cloud_fields($v));
}

/** نموذج اتصل بنا من الصفحة الرئيسية mizapos.com */
function activation_handle_website_contact(PDO $pdo, array $config): void
{
    require_once __DIR__ . '/mailer.php';
    $body = activation_json_body();
    if (trim((string) ($body['company'] ?? '')) !== '') {
        activation_json(200, ['ok' => true]);
    }

    $name = trim((string) ($body['name'] ?? ''));
    $email = strtolower(trim((string) ($body['email'] ?? '')));
    $phone = trim((string) ($body['phone'] ?? ''));
    $topic = trim((string) ($body['topic'] ?? 'استفسار عام'));
    $message = trim((string) ($body['message'] ?? ''));

    if ($name === '' || $email === '' || strpos($email, '@') === false) {
        activation_json(400, ['error' => 'validation', 'message' => 'الاسم والبريد مطلوبان.']);
    }
    $msgLen = function_exists('mb_strlen') ? mb_strlen($message) : strlen($message);
    if ($msgLen < 8) {
        activation_json(400, ['error' => 'validation', 'message' => 'الرسالة قصيرة جداً.']);
    }

    $to = trim((string) ($config['WEBSITE_CONTACT_EMAIL'] ?? 'hsnpal99@gmail.com'));
    if ($to === '' || strpos($to, '@') === false) {
        activation_json(500, ['error' => 'contact_not_configured']);
    }

    $id = activation_uuid();
    $now = activation_now_iso();
    $ip = (string) ($_SERVER['REMOTE_ADDR'] ?? '');
    $ua = (string) ($_SERVER['HTTP_USER_AGENT'] ?? '');

    $pdo->prepare(
        'INSERT INTO website_contact_messages '
        . '(id, name, email, phone, topic, message, ip, user_agent, mail_sent, created_at) '
        . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?)',
    )->execute([
        $id,
        $name,
        $email,
        $phone !== '' ? $phone : null,
        $topic,
        $message,
        $ip !== '' ? $ip : null,
        $ua !== '' ? $ua : null,
        $now,
    ]);

    $subject = 'MizaPos.com — ' . $topic;
    $safeName = htmlspecialchars($name, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    $safeEmail = htmlspecialchars($email, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    $safePhone = htmlspecialchars($phone !== '' ? $phone : '—', ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    $safeTopic = htmlspecialchars($topic, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    $safeMsg = nl2br(htmlspecialchars($message, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'));

    $html = '<div dir="rtl" style="font-family:Tahoma,Arial,sans-serif;line-height:1.7">'
        . '<h2 style="color:#00407B">رسالة من موقع MizaPos</h2>'
        . '<p><strong>الموضوع:</strong> ' . $safeTopic . '</p>'
        . '<p><strong>الاسم:</strong> ' . $safeName . '</p>'
        . '<p><strong>البريد:</strong> <a href="mailto:' . $safeEmail . '">' . $safeEmail . '</a></p>'
        . '<p><strong>الهاتف:</strong> ' . $safePhone . '</p>'
        . '<hr><p><strong>الرسالة:</strong></p><p>' . $safeMsg . '</p>'
        . '<p style="font-size:12px;color:#64748b">معرّف: '
        . htmlspecialchars($id, ENT_QUOTES, 'UTF-8') . ' — '
        . htmlspecialchars($ip, ENT_QUOTES, 'UTF-8')
        . '</p></div>';

    $sent = activation_send_website_contact_email($config, $to, $subject, $html, $name, $email);
    $mailSent = (bool) ($sent['ok'] ?? false);
    if ($mailSent) {
        $pdo->prepare('UPDATE website_contact_messages SET mail_sent = 1 WHERE id = ?')
            ->execute([$id]);
    }

    activation_json(200, [
        'ok' => true,
        'id' => $id,
        'mailSent' => $mailSent,
    ]);
}

/** @param array<string,mixed> $admin */
function activation_dispatch(PDO $pdo, array $config, string $method, string $path): void
{
    if ($method === 'OPTIONS') {
        activation_send(204, activation_cors_headers(), '');
    }

    $path = $path === '' ? '/' : $path;
    if ($path !== '/' && $path[0] !== '/') {
        $path = '/' . $path;
    }

    if ($method === 'GET' && $path === '/api/health') {
        activation_json(200, ['ok' => true]);
    }

    if ($method === 'POST' && $path === '/api/website/contact') {
        activation_handle_website_contact($pdo, $config);
    }

    if ($method === 'POST' && $path === '/api/subscriber/link-device') {
        $body = activation_json_body();
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        $password = (string) ($body['password'] ?? '');
        $deviceRaw = (string) ($body['deviceLinkCode'] ?? '');
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        if ($email === '' || strpos($email, '@') === false || $password === '' || trim($deviceRaw) === '') {
            activation_json(400, ['error' => 'validation']);
        }
        $installationId = activation_device_link_code_to_installation_id($deviceRaw);
        if ($installationId === null) {
            activation_json(400, ['error' => 'invalid_device_code']);
        }
        try {
            $upClaim = $pdo->prepare(
                'INSERT INTO device_link_claims (installation_id, organization_id, email_normalized, updated_at)
                 VALUES (?, ?, ?, ?)
                 ON CONFLICT(installation_id) DO UPDATE SET
                   organization_id = excluded.organization_id,
                   email_normalized = excluded.email_normalized,
                   updated_at = excluded.updated_at',
            );
            $upClaim->execute([$installationId, $organizationId, $email, activation_now_iso()]);
        } catch (Throwable $e) {
            error_log('[activation] link-device claim: ' . $e->getMessage());
        }
        $passwordMatches = activation_signup_rows_matching_password($pdo, $email, $password, $organizationId);
        $resolved = activation_pick_approved_signup_for_device_link($passwordMatches);
        $err = $resolved['error'] ?? '';
        if ($err === 'signup_not_approved') {
            activation_json(403, ['error' => 'signup_not_approved']);
        }
        if ($err === 'signup_rejected') {
            activation_json(403, ['error' => 'signup_rejected']);
        }
        if ($err === 'ambiguous') {
            activation_json(409, [
                'error' => 'ambiguous_organization',
                'organizationIds' => $resolved['organizationIds'] ?? [],
            ]);
        }
        $matched = $resolved['row'] ?? null;
        if ($matched === null) {
            activation_json(401, ['error' => 'invalid_credentials']);
        }
        [$code, $payload] = activation_redeem_for_installation($pdo, $matched, $installationId);
        if ($code !== 200) {
            activation_json($code, $payload);
        }
        activation_json(200, [
            'ok' => true,
            'organizationId' => $matched['organization_id'],
        ]);
    }

    /**
     * يخزّن ربط كود الجهاز + المؤسسة + البريد للوحة الإدارة (مفتاح التثبيت فقط — لا يُفعّل الاشتراك).
     * يُستدعى من البرنامج عند إدخال المشترك بريده في خطوة التفعيل.
     */
    if ($method === 'POST' && $path === '/api/device-link/claim') {
        activation_require_shared_secret($config);
        $body = activation_json_body();
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        $deviceRaw = trim((string) ($body['deviceLinkCode'] ?? ''));
        if ($organizationId === '' || strpos($email, '@') === false || $deviceRaw === '') {
            activation_json(400, ['error' => 'validation']);
        }
        $installationId = activation_device_link_code_to_installation_id($deviceRaw);
        if ($installationId === null) {
            activation_json(400, ['error' => 'invalid_device_code']);
        }
        try {
            $up = $pdo->prepare(
                'INSERT INTO device_link_claims (installation_id, organization_id, email_normalized, updated_at)
                 VALUES (?, ?, ?, ?)
                 ON CONFLICT(installation_id) DO UPDATE SET
                   organization_id = excluded.organization_id,
                   email_normalized = excluded.email_normalized,
                   updated_at = excluded.updated_at',
            );
            $up->execute([$installationId, $organizationId, $email, activation_now_iso()]);
            activation_apply_claim_email_to_activated_records($pdo, $installationId, $organizationId, $email);
            activation_json(200, ['ok' => true]);
        } catch (Throwable $e) {
            error_log('[activation] device-link/claim: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }
    }

    if ($method === 'POST' && $path === '/api/signup') {
        activation_require_shared_secret($config);
        $body = activation_json_body();
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        $fullName = trim((string) ($body['fullName'] ?? ''));
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        $dialCode = trim((string) ($body['dialCode'] ?? '')) ?: '+970';
        $phone = preg_replace('/\D/', '', (string) ($body['phone'] ?? '')) ?? '';

        if ($organizationId === '' || strlen($fullName) < 2 || strpos($email, '@') === false) {
            activation_json(400, ['error' => 'validation']);
        }
        if (strlen($phone) < 6) {
            activation_json(400, ['error' => 'validation']);
        }
        $password_hash = activation_resolve_signup_password_hash($body);
        if ($password_hash === null) {
            activation_json(400, ['error' => 'validation']);
        }

        $now = activation_now_iso();
        try {
            $pdo->beginTransaction();
            $st = $pdo->prepare(
                "SELECT id FROM signup_requests
                 WHERE organization_id = ? AND lower(trim(email)) = ? AND status = 'pending'",
            );
            $st->execute([$organizationId, $email]);
            $pending = $st->fetch(PDO::FETCH_ASSOC);
            if ($pending) {
                $up = $pdo->prepare(
                    "UPDATE signup_requests SET
                       full_name = ?, phone = ?, dial_code = ?, password_hash = ?, requested_at = ?
                     WHERE id = ?",
                );
                $pendingId = (string) $pending['id'];
                $up->execute([$fullName, $phone, $dialCode, $password_hash, $now, $pendingId]);
                $pdo->commit();
                activation_issue_signup_email_verification($pdo, $config, $pendingId);
                activation_json(200, ['ok' => true, 'emailVerificationSent' => true]);
            }

            $st2 = $pdo->prepare(
                "SELECT id FROM signup_requests
                 WHERE organization_id = ? AND lower(trim(email)) = ?
                   AND status = 'approved'",
            );
            $st2->execute([$organizationId, $email]);
            if ($st2->fetch(PDO::FETCH_ASSOC)) {
                $pdo->rollBack();
                activation_json(409, ['error' => 'activation_pending']);
            }

            $ins = $pdo->prepare(
                "INSERT INTO signup_requests (
                  id, organization_id, full_name, email, phone, dial_code, password_hash, requested_at, status
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending')",
            );
            $newId = activation_uuid();
            $ins->execute([
                $newId,
                $organizationId,
                $fullName,
                $email,
                $phone,
                $dialCode,
                $password_hash,
                $now,
            ]);
            $pdo->commit();
            activation_issue_signup_email_verification($pdo, $config, $newId);
            activation_json(200, ['ok' => true, 'emailVerificationSent' => true]);
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            error_log('[activation] signup: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }
    }

    if ($method === 'GET' && $path === '/api/verify-email') {
        $token = trim((string) ($_GET['token'] ?? ''));
        $result = activation_verify_signup_email_token($pdo, $token);
        if (!($result['ok'] ?? false)) {
            activation_json(400, $result);
        }
        activation_json(200, $result);
    }

    if ($method === 'POST' && $path === '/api/signup/resend-verification') {
        activation_require_shared_secret($config);
        $body = activation_json_body();
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        if ($organizationId === '' || strpos($email, '@') === false) {
            activation_json(400, ['error' => 'validation']);
        }
        $st = $pdo->prepare(
            "SELECT id FROM signup_requests
             WHERE trim(organization_id) = trim(?) AND lower(trim(email)) = ?
             ORDER BY requested_at DESC LIMIT 1",
        );
        $st->execute([$organizationId, $email]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            activation_json(404, ['error' => 'not_found']);
        }
        $send = activation_issue_signup_email_verification($pdo, $config, (string) $row['id']);
        if (!($send['ok'] ?? false) && !($send['skipped'] ?? false)) {
            activation_json(500, ['error' => 'mail_failed']);
        }
        activation_json(200, [
            'ok' => true,
            'skipped' => (bool) ($send['skipped'] ?? false),
        ]);
    }

    /* -------- Subscriber auth (account + voucher activation) -------- */

    if ($method === 'POST' && $path === '/api/auth/register') {
        activation_require_shared_secret($config);
        $body = activation_json_body();
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        $fullName = trim((string) ($body['fullName'] ?? '')) ?: $email;
        $dialCode = trim((string) ($body['dialCode'] ?? '')) ?: '+970';
        $phone = (string) preg_replace('/\D/', '', (string) ($body['phone'] ?? '')) ?? '';
        if ($organizationId === '' || strpos($email, '@') === false) {
            activation_json(400, ['error' => 'validation']);
        }
        $passwordHash = activation_resolve_signup_password_hash($body);
        if ($passwordHash === null) {
            activation_json(400, ['error' => 'weak_password']);
        }
        $now = activation_now_iso();
        try {
            $pdo->beginTransaction();
            $st = $pdo->prepare(
                "SELECT id, status FROM signup_requests
                 WHERE trim(organization_id) = trim(?) AND lower(trim(email)) = ?
                 ORDER BY requested_at DESC LIMIT 1",
            );
            $st->execute([$organizationId, $email]);
            $row = $st->fetch(PDO::FETCH_ASSOC);
            if ($row) {
                $up = $pdo->prepare(
                    "UPDATE signup_requests SET
                       full_name = ?, phone = ?, dial_code = ?, password_hash = ?,
                       status = 'approved', reviewed_at = ?
                     WHERE id = ?",
                );
                $up->execute([$fullName, $phone, $dialCode, $passwordHash, $now, $row['id']]);
                $sid = (string) $row['id'];
            } else {
                $sid = activation_uuid();
                $ins = $pdo->prepare(
                    "INSERT INTO signup_requests (
                       id, organization_id, full_name, email, phone, dial_code,
                       password_hash, requested_at, status, reviewed_at
                     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'approved', ?)",
                );
                $ins->execute([
                    $sid, $organizationId, $fullName, $email,
                    $phone, $dialCode, $passwordHash, $now, $now,
                ]);
            }
            $pdo->commit();
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            error_log('[activation] auth/register: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }
        activation_issue_signup_email_verification($pdo, $config, $sid);
        $token = activation_jwt_sign(
            [
                'role' => 'subscriber',
                'sub' => $sid,
                'email' => $email,
                'organizationId' => $organizationId,
                'exp' => time() + 86400 * 30,
            ],
            activation_jwt_secret($config),
        );
        $verifiedSt = $pdo->prepare('SELECT email_verified FROM signup_requests WHERE id = ? LIMIT 1');
        $verifiedSt->execute([$sid]);
        $verifiedRow = $verifiedSt->fetch(PDO::FETCH_ASSOC);
        activation_json(200, [
            'ok' => true,
            'token' => $token,
            'email' => $email,
            'organizationId' => $organizationId,
            'fullName' => $fullName,
            'phone' => $phone,
            'dialCode' => $dialCode,
            'emailVerified' => (int) ($verifiedRow['email_verified'] ?? 0) === 1,
            'emailVerificationSent' => true,
        ]);
    }

    if ($method === 'GET' && $path === '/api/auth/login') {
        activation_json(405, [
            'ok' => false,
            'error' => 'method_not_allowed',
            'hint' => 'This endpoint requires POST with JSON: {"email":"...","password":"..."}',
        ]);
    }

    if ($method === 'POST' && $path === '/api/auth/login') {
        activation_require_shared_secret($config);
        $body = activation_json_body();
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        $password = (string) ($body['password'] ?? '');
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        if (strpos($email, '@') === false || strlen($password) < 4) {
            activation_json(400, ['error' => 'validation']);
        }
        if ($organizationId !== '') {
            $st = $pdo->prepare(
                "SELECT * FROM signup_requests
                 WHERE trim(organization_id) = trim(?) AND lower(trim(email)) = ?
                 ORDER BY requested_at DESC LIMIT 1",
            );
            $st->execute([$organizationId, $email]);
        } else {
            $st = $pdo->prepare(
                "SELECT * FROM signup_requests
                 WHERE lower(trim(email)) = ?
                 ORDER BY requested_at DESC LIMIT 1",
            );
            $st->execute([$email]);
        }
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row || !password_verify($password, (string) $row['password_hash'])) {
            activation_json(401, ['error' => 'unauthorized']);
        }
        $token = activation_jwt_sign(
            [
                'role' => 'subscriber',
                'sub' => $row['id'],
                'email' => strtolower(trim((string) $row['email'])),
                'organizationId' => (string) $row['organization_id'],
                'exp' => time() + 86400 * 30,
            ],
            activation_jwt_secret($config),
        );
        activation_json(200, [
            'ok' => true,
            'token' => $token,
            'email' => strtolower(trim((string) $row['email'])),
            'organizationId' => (string) $row['organization_id'],
            'fullName' => (string) $row['full_name'],
            'phone' => (string) ($row['phone'] ?? ''),
            'dialCode' => (string) ($row['dial_code'] ?? ''),
            'emailVerified' => (int) ($row['email_verified'] ?? 0) === 1,
        ]);
    }

    if ($method === 'GET' && $path === '/api/auth/me') {
        $me = activation_require_subscriber($config, $pdo);
        $verifiedSt = $pdo->prepare(
            'SELECT email_verified FROM signup_requests WHERE id = ? LIMIT 1',
        );
        $verifiedSt->execute([$me['signup_request_id']]);
        $verifiedRow = $verifiedSt->fetch(PDO::FETCH_ASSOC);
        activation_json(200, [
            'ok' => true,
            'email' => $me['email'],
            'organizationId' => $me['organization_id'],
            'fullName' => $me['full_name'],
            'phone' => $me['phone'],
            'dialCode' => $me['dial_code'],
            'emailVerified' => (int) ($verifiedRow['email_verified'] ?? 0) === 1,
        ]);
    }

    if ($method === 'POST' && $path === '/api/auth/change-password') {
        activation_require_shared_secret($config);
        $me = activation_require_subscriber($config, $pdo);
        $body = activation_json_body();
        $oldPassword = (string) ($body['oldPassword'] ?? '');
        $newPassword = (string) ($body['newPassword'] ?? '');
        if (strlen($newPassword) < 4) {
            activation_json(400, ['error' => 'weak_password']);
        }
        $st = $pdo->prepare('SELECT password_hash FROM signup_requests WHERE id = ?');
        $st->execute([$me['signup_request_id']]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row || !password_verify($oldPassword, (string) $row['password_hash'])) {
            activation_json(401, ['error' => 'wrong_password']);
        }
        $hash = password_hash($newPassword, PASSWORD_BCRYPT, ['cost' => 10]);
        $up = $pdo->prepare('UPDATE signup_requests SET password_hash = ? WHERE id = ?');
        $up->execute([$hash, $me['signup_request_id']]);
        activation_json(200, ['ok' => true]);
    }

    if ($method === 'POST' && $path === '/api/auth/forgot-password') {
        activation_require_shared_secret($config);
        $body = activation_json_body();
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        if (strpos($email, '@') === false) {
            activation_json(400, ['error' => 'validation']);
        }
        $st = $pdo->prepare(
            "SELECT id, full_name FROM signup_requests
             WHERE lower(trim(email)) = ?
             ORDER BY requested_at DESC
             LIMIT 1",
        );
        $st->execute([$email]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            activation_json(404, ['error' => 'email_not_found']);
        }
        $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
        $temp = '';
        for ($i = 0; $i < 10; $i++) {
            $temp .= $alphabet[random_int(0, strlen($alphabet) - 1)];
        }
        $hash = password_hash($temp, PASSWORD_BCRYPT, ['cost' => 10]);
        $up = $pdo->prepare('UPDATE signup_requests SET password_hash = ? WHERE id = ?');
        $up->execute([$hash, (string) $row['id']]);
        $name = trim((string) ($row['full_name'] ?? '')) ?: $email;
        $subject = 'MizaPos — كلمة مرور مؤقتة';
        $html = '<div dir="rtl" style="font-family:Cairo,sans-serif">'
            . '<p>مرحباً ' . htmlspecialchars($name, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') . '،</p>'
            . '<p>طُلبت إعادة تعيين كلمة المرور لحسابك في MizaPos.</p>'
            . '<p><strong>كلمة المرور المؤقتة:</strong> '
            . htmlspecialchars($temp, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8')
            . '</p>'
            . '<p>سجّل الدخول ثم غيّر كلمة المرور من إعدادات الحساب إن أمكن.</p>'
            . '<p style="color:#64748b;font-size:12px">إن لم تطلب ذلك، تجاهل هذه الرسالة.</p>'
            . '</div>';
        $res = activation_send_email($config, $email, $subject, $html);
        if (!empty($res['ok'])) {
            activation_json(200, ['ok' => true]);
        }
        $err = (string) ($res['error'] ?? 'mail_failed');
        if (in_array($err, ['disabled', 'from_not_configured'], true)) {
            activation_json(503, ['error' => 'smtp_missing']);
        }
        activation_json(500, ['error' => 'mail_failed']);
    }

    /* -------- Voucher redemption & status -------- */

    if ($method === 'POST' && $path === '/api/voucher/redeem') {
        activation_require_shared_secret($config);
        $me = activation_require_subscriber($config, $pdo);
        $body = activation_json_body();
        $code = activation_voucher_normalize((string) ($body['code'] ?? ''));
        $installationId = activation_normalize_installation_id((string) ($body['installationId'] ?? ''));
        if ($code === '' || strlen($installationId) < 8) {
            activation_json(400, ['error' => 'invalid_voucher']);
        }
        $deviceFingerprint = trim((string) ($body['deviceFingerprint'] ?? ''));
        $computerName = trim((string) ($body['computerName'] ?? ''));
        $osName = trim((string) ($body['osName'] ?? ''));
        $osUser = trim((string) ($body['osUser'] ?? ''));
        $devicePlatform = activation_normalize_device_platform(
            (string) ($body['devicePlatform'] ?? ''),
            $osName,
        );
        $now = activation_now_iso();

        try {
            $pdo->beginTransaction();
            $st = $pdo->prepare('SELECT * FROM vouchers WHERE code = ? LIMIT 1');
            $st->execute([$code]);
            $v = $st->fetch(PDO::FETCH_ASSOC);
            if (!$v) {
                $pdo->rollBack();
                activation_json(404, ['error' => 'voucher_not_found']);
            }
            if ((string) $v['status'] === 'revoked') {
                $pdo->rollBack();
                activation_json(403, ['error' => 'voucher_revoked', 'reason' => (string) ($v['revoke_reason'] ?? '')]);
            }
            $boundEmail = strtolower(trim((string) ($v['redeemed_by_email'] ?? '')));
            $boundOrg = trim((string) ($v['redeemed_by_organization_id'] ?? ''));
            $isBound = $boundEmail !== '' && $boundOrg !== '';
            if ($isBound && ($boundEmail !== $me['email'] || $boundOrg !== $me['organization_id'])) {
                $pdo->rollBack();
                activation_json(409, ['error' => 'voucher_bound_to_other']);
            }

            activation_voucher_dedupe_redemptions($pdo, $code);
            $usedDevices = activation_voucher_active_device_count($pdo, $code);

            $stThis = $pdo->prepare(
                'SELECT installation_id, revoked_at FROM voucher_redemptions
                 WHERE voucher_code = ? AND lower(trim(installation_id)) = ? LIMIT 1',
            );
            $stThis->execute([$code, $installationId]);
            $thisRow = $stThis->fetch(PDO::FETCH_ASSOC);
            $canonicalInstallId = $thisRow
                ? (string) $thisRow['installation_id']
                : $installationId;

            if (!$thisRow) {
                $slotErr = activation_voucher_device_slot_error(
                    $pdo,
                    $v,
                    $code,
                    $devicePlatform,
                    true,
                );
                if ($slotErr !== null) {
                    $pdo->rollBack();
                    activation_json(409, $slotErr);
                }
                $ins = $pdo->prepare(
                    'INSERT INTO voucher_redemptions (
                       voucher_code, installation_id, organization_id, subscriber_email,
                       device_fingerprint, computer_name, os_name, os_user, device_platform,
                       redeemed_at, last_seen_at
                     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                );
                $ins->execute([
                    $code, $canonicalInstallId, $me['organization_id'], $me['email'],
                    $deviceFingerprint, $computerName, $osName, $osUser, $devicePlatform,
                    $now, $now,
                ]);
            } elseif (!empty($thisRow['revoked_at'])) {
                $slotErr = activation_voucher_device_slot_error(
                    $pdo,
                    $v,
                    $code,
                    $devicePlatform,
                    true,
                );
                if ($slotErr !== null) {
                    $pdo->rollBack();
                    activation_json(409, $slotErr);
                }
                $up = $pdo->prepare(
                    'UPDATE voucher_redemptions SET
                       revoked_at = NULL,
                       organization_id = ?, subscriber_email = ?,
                       device_fingerprint = ?, computer_name = ?, os_name = ?, os_user = ?,
                       device_platform = ?,
                       redeemed_at = ?, last_seen_at = ?
                     WHERE voucher_code = ? AND installation_id = ?',
                );
                $up->execute([
                    $me['organization_id'], $me['email'],
                    $deviceFingerprint, $computerName, $osName, $osUser, $devicePlatform,
                    $now, $now, $code, $canonicalInstallId,
                ]);
            } else {
                $up = $pdo->prepare(
                    'UPDATE voucher_redemptions SET
                       computer_name = ?, os_name = ?, os_user = ?, device_platform = ?, last_seen_at = ?
                     WHERE voucher_code = ? AND installation_id = ?',
                );
                $up->execute([
                    $computerName, $osName, $osUser, $devicePlatform, $now,
                    $code, $canonicalInstallId,
                ]);
            }

            if (!$isBound) {
                $upv = $pdo->prepare(
                    "UPDATE vouchers SET
                       status = 'redeemed',
                       first_redeemed_at = COALESCE(first_redeemed_at, ?),
                       redeemed_by_email = ?,
                       redeemed_by_organization_id = ?
                     WHERE code = ?",
                );
                $upv->execute([$now, $me['email'], $me['organization_id'], $code]);
                distributor_license_apply_voucher_cloud_on_redeem($pdo, $code);
            } else {
                $upv = $pdo->prepare(
                    "UPDATE vouchers SET status = CASE WHEN status = 'unused' THEN 'redeemed' ELSE status END
                     WHERE code = ?",
                );
                $upv->execute([$code]);
            }
            $pdo->commit();
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            error_log('[activation] voucher/redeem: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }

        $used = activation_voucher_active_device_count($pdo, $code);
        activation_json(200, array_merge([
            'ok' => true,
            'code' => $code,
            'usedDevices' => $used,
            'status' => 'active',
            'devicePlatform' => $devicePlatform,
        ], activation_voucher_public_fields($pdo, $v, $code)));
    }

    if ($method === 'GET' && $path === '/api/voucher/status') {
        $me = activation_require_subscriber($config, $pdo);
        $installationId = activation_normalize_installation_id((string) ($_GET['installationId'] ?? ''));
        if (strlen($installationId) < 8) {
            activation_json(400, ['error' => 'validation']);
        }
        $st = $pdo->prepare(
            'SELECT v.code, v.max_devices, v.max_desktop_devices, v.max_android_devices,
                    v.status AS vstatus, v.revoke_reason,
                    vr.installation_id, vr.revoked_at AS device_revoked_at, vr.redeemed_at, vr.last_seen_at
             FROM voucher_redemptions vr
             INNER JOIN vouchers v ON v.code = vr.voucher_code
             WHERE lower(trim(vr.installation_id)) = ?
               AND vr.subscriber_email = ?
               AND vr.organization_id = ?
             ORDER BY vr.last_seen_at DESC
             LIMIT 1',
        );
        $st->execute([$installationId, $me['email'], $me['organization_id']]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            activation_json(200, [
                'ok' => true,
                'status' => 'none',
                'email' => $me['email'],
                'organizationId' => $me['organization_id'],
            ]);
        }
        $vstatus = (string) $row['vstatus'];
        $deviceRevoked = !empty($row['device_revoked_at']);
        $status = 'active';
        if ($vstatus === 'revoked') {
            $status = 'revoked';
        } elseif ($deviceRevoked) {
            $status = 'device_revoked';
        }
        $voucherCode = (string) $row['code'];
        $used = activation_voucher_active_device_count($pdo, $voucherCode);
        $now = activation_now_iso();
        $canonicalInstallId = (string) ($row['installation_id'] ?? $installationId);
        $pdo->prepare(
            'UPDATE voucher_redemptions SET last_seen_at = ?
             WHERE voucher_code = ? AND installation_id = ?',
        )->execute([$now, $voucherCode, $canonicalInstallId]);

        activation_json(200, array_merge([
            'ok' => true,
            'status' => $status,
            'code' => $voucherCode,
            'usedDevices' => $used,
            'redeemedAt' => (string) ($row['redeemed_at'] ?? ''),
            'revokeReason' => (string) ($row['revoke_reason'] ?? ''),
            'email' => $me['email'],
            'organizationId' => $me['organization_id'],
        ], activation_voucher_public_fields($pdo, [
            'code' => $voucherCode,
            'max_devices' => (int) $row['max_devices'],
            'max_desktop_devices' => $row['max_desktop_devices'] ?? null,
            'max_android_devices' => $row['max_android_devices'] ?? null,
        ], $voucherCode)));
    }

    if ($method === 'POST' && $path === '/api/voucher/release-device') {
        activation_require_shared_secret($config);
        $me = activation_require_subscriber($config, $pdo);
        $body = activation_json_body();
        $code = activation_voucher_normalize((string) ($body['code'] ?? ''));
        $installationId = activation_normalize_installation_id((string) ($body['installationId'] ?? ''));
        if ($code === '' || strlen($installationId) < 8) {
            activation_json(400, ['error' => 'validation']);
        }
        $check = $pdo->prepare(
            'SELECT installation_id FROM voucher_redemptions
             WHERE voucher_code = ? AND lower(trim(installation_id)) = ?
               AND subscriber_email = ? AND organization_id = ?
             LIMIT 1',
        );
        $check->execute([$code, $installationId, $me['email'], $me['organization_id']]);
        $found = $check->fetch(PDO::FETCH_ASSOC);
        if (!$found) {
            activation_json(404, ['error' => 'not_found']);
        }
        $canonicalInstallId = (string) ($found['installation_id'] ?? $installationId);
        $now = activation_now_iso();
        $pdo->prepare(
            'UPDATE voucher_redemptions SET revoked_at = ?
             WHERE voucher_code = ? AND installation_id = ? AND revoked_at IS NULL',
        )->execute([$now, $code, $canonicalInstallId]);
        activation_json(200, ['ok' => true]);
    }

    if ($method === 'POST' && $path === '/api/redeem') {
        activation_require_shared_secret($config);
        $body = activation_json_body();
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        $compact = activation_norm_activation_code((string) ($body['activationCode'] ?? ''));
        $installationId = trim((string) ($body['installationId'] ?? ''));
        if ($organizationId === '' || strlen($installationId) < 8) {
            activation_json(400, ['error' => 'validation']);
        }

        $matched = null;
        if ($compact !== '') {
            $st = $pdo->prepare(
                "SELECT * FROM signup_requests
                 WHERE organization_id = ? AND status = 'approved'
                   AND issued_activation_key IS NOT NULL
                   AND length(trim(issued_activation_key)) > 0
                 ORDER BY COALESCE(reviewed_at, requested_at) DESC",
            );
            $st->execute([$organizationId]);
            $rows = $st->fetchAll(PDO::FETCH_ASSOC);
            foreach ($rows as $r) {
                $norm = activation_norm_activation_code((string) ($r['issued_activation_key'] ?? ''));
                if ($norm !== '' && $norm === $compact) {
                    $matched = $r;
                    break;
                }
            }
        }
        if ($matched === null) {
            $stFb = $pdo->prepare(
                "SELECT sr.* FROM activation_redeems ar
                 INNER JOIN signup_requests sr ON sr.id = ar.signup_request_id
                 WHERE ar.installation_id = ?
                   AND trim(sr.organization_id) = trim(?)
                   AND sr.status = 'approved'
                 ORDER BY ar.redeemed_at DESC
                 LIMIT 1",
            );
            $stFb->execute([$installationId, $organizationId]);
            $matched = $stFb->fetch(PDO::FETCH_ASSOC) ?: null;
        }
        if ($matched === null) {
            activation_json(404, ['error' => 'not_found']);
        }
        [$redeemCode, $redeemBody] = activation_redeem_for_installation($pdo, $matched, $installationId);
        activation_json($redeemCode, $redeemBody);
    }

    if ($method === 'POST' && $path === '/api/license-report') {
        activation_require_shared_secret($config);
        $body = activation_json_body();
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        if ($organizationId === '' || strpos($email, '@') === false) {
            activation_json(400, ['error' => 'validation']);
        }
        $trial = null;
        if (!empty($body['trialEndAt']) && is_string($body['trialEndAt'])) {
            $t = trim($body['trialEndAt']);
            $trial = $t !== '' ? $t : null;
        }
        $sub = null;
        if (!empty($body['subscriptionAnnualUntil']) && is_string($body['subscriptionAnnualUntil'])) {
            $t = trim($body['subscriptionAnnualUntil']);
            $sub = $t !== '' ? $t : null;
        }
        $legacy = !empty($body['legacyActivated']);
        $binding = activation_parse_device_binding((string) ($body['subscriptionDeviceBinding'] ?? ''));
        $now = activation_now_iso();
        try {
            $up = $pdo->prepare(
                'INSERT INTO license_snapshots (
                    organization_id, email_normalized, trial_end_at, subscription_annual_until, legacy_activated, updated_at, admin_valid_until, access_suspended
                ) VALUES (?, ?, ?, ?, ?, ?, NULL, 0)
                ON CONFLICT(organization_id, email_normalized) DO UPDATE SET
                    trial_end_at = excluded.trial_end_at,
                    subscription_annual_until = excluded.subscription_annual_until,
                    legacy_activated = excluded.legacy_activated,
                    updated_at = excluded.updated_at',
            );
            $up->execute([$organizationId, $email, $trial, $sub, $legacy ? 1 : 0, $now]);
            if ($binding !== null) {
                $upDev = $pdo->prepare(
                    'INSERT INTO subscriber_devices (
                        id, organization_id, email_normalized, installation_id, device_fingerprint, computer_name, os_user, os_name, last_seen_at, revoked_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                    ON CONFLICT(organization_id, email_normalized, installation_id) DO UPDATE SET
                        device_fingerprint = excluded.device_fingerprint,
                        computer_name = excluded.computer_name,
                        os_user = excluded.os_user,
                        os_name = excluded.os_name,
                        last_seen_at = excluded.last_seen_at,
                        revoked_at = NULL',
                );
                $upDev->execute([
                    activation_uuid(),
                    $organizationId,
                    $email,
                    $binding['installationId'],
                    $binding['fingerprint'],
                    $binding['computerName'],
                    $binding['osUser'],
                    $binding['osName'],
                    $now,
                ]);
            }
        } catch (Throwable $e) {
            error_log('[activation] license-report: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }
        activation_json(200, ['ok' => true]);
    }

    if ($method === 'GET' && $path === '/api/license-pull') {
        activation_require_shared_secret($config);
        $organizationId = trim((string) ($_GET['organizationId'] ?? ''));
        $email = strtolower(trim((string) ($_GET['email'] ?? '')));
        $installationId = trim((string) ($_GET['installationId'] ?? ''));
        if ($organizationId === '' || strpos($email, '@') === false) {
            activation_json(400, ['error' => 'validation']);
        }
        $broadcastNotice = activation_broadcast_notice_for_client($pdo, $installationId);
        $stSu = $pdo->prepare(
            'SELECT 1 FROM signup_requests WHERE organization_id = ? AND lower(trim(email)) = ? LIMIT 1',
        );
        $stSu->execute([$organizationId, $email]);
        $hasSignupRequest = (bool) $stSu->fetchColumn();
        $st = $pdo->prepare(
            'SELECT * FROM license_snapshots WHERE organization_id = ? AND email_normalized = ?',
        );
        $st->execute([$organizationId, $email]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            $distFields = distributor_license_public_fields($pdo, $organizationId);
            activation_json(200, array_merge([
                'ok' => true,
                'accessSuspended' => false,
                'subscriptionAnnualUntil' => null,
                'trialEndAt' => null,
                'legacyActivated' => false,
                'hasLicenseSnapshot' => false,
                'hasSignupRequest' => $hasSignupRequest,
                'broadcastNotice' => $broadcastNotice,
            ], $distFields));
        }
        $suspended = !empty($row['access_suspended']);
        $effectiveSub = null;
        if (!$suspended) {
            $effectiveSub = activation_latest_iso_date(
                isset($row['admin_valid_until']) ? (string) $row['admin_valid_until'] : null,
                isset($row['subscription_annual_until']) ? (string) $row['subscription_annual_until'] : null,
            );
        }
        $distFields = distributor_license_public_fields($pdo, $organizationId);
        activation_json(200, array_merge([
            'ok' => true,
            'accessSuspended' => $suspended,
            'subscriptionAnnualUntil' => $effectiveSub,
            'trialEndAt' => $row['trial_end_at'] ?? null,
            'legacyActivated' => !empty($row['legacy_activated']),
            'hasLicenseSnapshot' => true,
            'hasSignupRequest' => $hasSignupRequest,
            'broadcastNotice' => $broadcastNotice,
        ], $distFields));
    }

    if ($method === 'GET' && $path === '/api/broadcast-notice') {
        activation_require_shared_secret($config);
        $installationId = trim((string) ($_GET['installationId'] ?? ''));
        if ($installationId === '') {
            activation_json(400, ['error' => 'validation']);
        }
        activation_json(200, [
            'ok' => true,
            'notice' => activation_broadcast_notice_for_client($pdo, $installationId),
        ]);
    }

    if ($method === 'POST' && $path === '/api/broadcast-notice/dismiss') {
        activation_require_shared_secret($config);
        $body = activation_json_body();
        $noticeId = trim((string) ($body['noticeId'] ?? ''));
        $installationId = trim((string) ($body['installationId'] ?? ''));
        if ($noticeId === '' || $installationId === '') {
            activation_json(400, ['error' => 'validation']);
        }
        $chk = $pdo->prepare('SELECT 1 FROM broadcast_notices WHERE id = ? LIMIT 1');
        $chk->execute([$noticeId]);
        if (!$chk->fetchColumn()) {
            activation_json(404, ['error' => 'not_found']);
        }
        $now = activation_now_iso();
        $ins = $pdo->prepare(
            'INSERT OR IGNORE INTO broadcast_notice_dismissals (notice_id, installation_id, dismissed_at)
             VALUES (?, ?, ?)',
        );
        $ins->execute([$noticeId, $installationId, $now]);
        activation_json(200, ['ok' => true]);
    }

    if ($method === 'POST' && $path === '/api/signup-delete') {
        activation_require_shared_secret($config);
        $body = activation_json_body();
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        if ($organizationId === '' || strpos($email, '@') === false) {
            activation_json(400, ['error' => 'validation']);
        }
        try {
            $pdo->prepare(
                'DELETE FROM license_snapshots WHERE organization_id = ? AND email_normalized = ?',
            )->execute([$organizationId, $email]);
            $st = $pdo->prepare(
                'DELETE FROM signup_requests WHERE organization_id = ? AND lower(trim(email)) = ?',
            );
            $st->execute([$organizationId, $email]);
            $n = $st->rowCount();
            activation_json(200, ['ok' => true, 'deleted' => $n]);
        } catch (Throwable $e) {
            error_log('[activation] signup-delete: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }
    }

    if ($method === 'POST' && $path === '/api/signup-sync') {
        activation_require_shared_secret($config);
        $body = activation_json_body();
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        if ($organizationId === '' || strpos($email, '@') === false) {
            activation_json(400, ['error' => 'validation']);
        }
        $fullName = array_key_exists('fullName', $body) ? trim((string) $body['fullName']) : null;
        $phone = array_key_exists('phone', $body)
            ? (preg_replace('/\D/', '', (string) $body['phone']) ?? '')
            : null;
        $dialCode = array_key_exists('dialCode', $body)
            ? (trim((string) $body['dialCode']) ?: '+970')
            : null;
        $passwordHashIn = trim((string) ($body['passwordHash'] ?? ''));
        $passwordHash = null;
        if ($passwordHashIn !== '') {
            if (!preg_match('/^\$(2a|2b|2y)\$/', $passwordHashIn)) {
                activation_json(400, ['error' => 'validation']);
            }
            $passwordHash = $passwordHashIn;
        }
        $sets = [];
        $args = [];
        if ($fullName !== null && $fullName !== '') {
            $sets[] = 'full_name = ?';
            $args[] = $fullName;
        }
        if ($phone !== null && strlen($phone) >= 6) {
            $sets[] = 'phone = ?';
            $args[] = $phone;
        }
        if ($dialCode !== null) {
            $sets[] = 'dial_code = ?';
            $args[] = $dialCode;
        }
        if ($passwordHash !== null) {
            $sets[] = 'password_hash = ?';
            $args[] = $passwordHash;
        }
        if ($sets === []) {
            activation_json(200, ['ok' => true, 'updated' => 0]);
        }
        try {
            $sql = 'UPDATE signup_requests SET ' . implode(', ', $sets)
                . ' WHERE organization_id = ? AND lower(trim(email)) = ?';
            $args[] = $organizationId;
            $args[] = $email;
            $st = $pdo->prepare($sql);
            $st->execute($args);
            activation_json(200, ['ok' => true, 'updated' => $st->rowCount()]);
        } catch (Throwable $e) {
            error_log('[activation] signup-sync: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }
    }

    if ($method === 'POST' && $path === '/admin/login') {
        $body = activation_json_body();
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        $password = (string) ($body['password'] ?? '');
        $secret = activation_jwt_secret($config);

        $c = (int) $pdo->query('SELECT COUNT(*) AS c FROM admins')->fetch(PDO::FETCH_ASSOC)['c'];
        $adminHash = (string) $config['ADMIN_PASSWORD_HASH'];

        if ($c === 0 && $adminHash !== '') {
            if (strlen($password) < 4) {
                activation_json(400, ['error' => 'validation']);
            }
            if (!password_verify($password, $adminHash)) {
                activation_json(401, ['error' => 'unauthorized']);
            }
            $token = activation_jwt_sign(
                [
                    'role' => 'admin',
                    'sub' => 'legacy-env',
                    'email' => '',
                    'legacy' => true,
                    'acl' => 'approver',
                    'exp' => time() + 43200,
                ],
                $secret,
            );
            activation_json(200, ['token' => $token, 'legacy' => true, 'acl' => 'approver']);
        }

        if ($c === 0 && $adminHash === '') {
            activation_json(503, ['error' => 'admin_not_configured']);
        }

        if (strpos($email, '@') === false || strlen($password) < 4) {
            activation_json(400, ['error' => 'validation']);
        }

        $st = $pdo->prepare('SELECT * FROM admins WHERE lower(trim(email)) = ?');
        $st->execute([$email]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if ($row && !empty($row['disabled_at'])) {
            activation_json(403, ['error' => 'disabled']);
        }
        if (!$row || !password_verify($password, (string) $row['password_hash'])) {
            activation_json(401, ['error' => 'unauthorized']);
        }
        $acl = (($row['acl'] ?? '') === 'viewer') ? 'viewer' : 'approver';
        $adminRole = strtolower(trim((string) ($row['admin_role'] ?? '')));
        if (!in_array($adminRole, ['admin', 'billing', 'support', 'viewer'], true)) {
            $adminRole = $acl === 'viewer' ? 'viewer' : 'admin';
        }
        $token = activation_jwt_sign(
            [
                'role' => 'admin',
                'sub' => $row['id'],
                'email' => $row['email'],
                'acl' => $acl,
                'adminRole' => $adminRole,
                'exp' => time() + 43200,
            ],
            $secret,
        );
        activation_json(200, ['token' => $token, 'legacy' => false, 'acl' => $acl, 'adminRole' => $adminRole]);
    }

    if ($method === 'GET' && $path === '/admin/admins') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'delete'); // only admin role (has delete) manages admins
        $st = $pdo->query('SELECT id, email, admin_role, created_at, disabled_at FROM admins ORDER BY created_at DESC');
        activation_json(200, ['items' => $st->fetchAll(PDO::FETCH_ASSOC)]);
    }

    if ($method === 'POST' && $path === '/admin/admins/create') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'delete');
        $body = activation_json_body();
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        $password = (string) ($body['password'] ?? '');
        $role = strtolower(trim((string) ($body['role'] ?? 'viewer')));
        if (strpos($email, '@') === false || strlen($password) < 8) {
            activation_json(400, ['error' => 'validation']);
        }
        if (!in_array($role, ['admin', 'billing', 'support', 'viewer'], true)) {
            $role = 'viewer';
        }
        try {
            $ok = activation_admin_insert($pdo, $email, $password, $role);
            if (!$ok) {
                activation_json(409, ['error' => 'exists']);
            }
            activation_log_subscriber_event($pdo, 'admin', 'admin', $admin, 'admin_created', [
                'email' => $email,
                'role' => $role,
            ]);
            activation_json(200, ['ok' => true]);
        } catch (InvalidArgumentException $e) {
            activation_json(400, ['error' => 'validation']);
        } catch (Throwable $e) {
            error_log('[activation] admins/create: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }
    }

    if ($method === 'POST' && $path === '/admin/admins/update') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'delete');
        $body = activation_json_body();
        $id = trim((string) ($body['id'] ?? ''));
        $role = strtolower(trim((string) ($body['role'] ?? '')));
        if ($id === '' || !in_array($role, ['admin', 'billing', 'support', 'viewer'], true)) {
            activation_json(400, ['error' => 'validation']);
        }
        $acl = $role === 'viewer' ? 'viewer' : 'approver';
        $up = $pdo->prepare('UPDATE admins SET admin_role = ?, acl = ? WHERE id = ?');
        $up->execute([$role, $acl, $id]);
        activation_log_subscriber_event($pdo, 'admin', 'admin', $admin, 'admin_role_updated', [
            'id' => $id,
            'role' => $role,
        ]);
        activation_json(200, ['ok' => true, 'updated' => $up->rowCount()]);
    }

    if ($method === 'POST' && $path === '/admin/admins/toggle') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'delete');
        $body = activation_json_body();
        $id = trim((string) ($body['id'] ?? ''));
        $enabled = !empty($body['enabled']);
        if ($id === '') {
            activation_json(400, ['error' => 'validation']);
        }
        $ts = $enabled ? null : activation_now_iso();
        $up = $pdo->prepare('UPDATE admins SET disabled_at = ? WHERE id = ?');
        $up->execute([$ts, $id]);
        activation_log_subscriber_event($pdo, 'admin', 'admin', $admin, 'admin_toggled', [
            'id' => $id,
            'enabled' => $enabled,
        ]);
        activation_json(200, ['ok' => true, 'updated' => $up->rowCount()]);
    }

    if ($method === 'POST' && $path === '/admin/admins/reset_password') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'delete');
        $body = activation_json_body();
        $id = trim((string) ($body['id'] ?? ''));
        $password = (string) ($body['password'] ?? '');
        if ($id === '' || strlen($password) < 8) {
            activation_json(400, ['error' => 'validation']);
        }
        $hash = password_hash($password, PASSWORD_BCRYPT, ['cost' => 10]);
        $up = $pdo->prepare('UPDATE admins SET password_hash = ? WHERE id = ?');
        $up->execute([$hash, $id]);
        activation_log_subscriber_event($pdo, 'admin', 'admin', $admin, 'admin_password_reset', [
            'id' => $id,
        ]);
        activation_json(200, ['ok' => true, 'updated' => $up->rowCount()]);
    }

    if ($method === 'GET' && $path === '/admin/admins/audit') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'delete');
        $limit = (int) ($_GET['limit'] ?? 50);
        if ($limit < 1) {
            $limit = 50;
        }
        if ($limit > 500) {
            $limit = 500;
        }
        $eventType = strtolower(trim((string) ($_GET['eventType'] ?? 'all')));
        $q = trim((string) ($_GET['q'] ?? ''));
        $allowedEvents = [
            'all',
            'admin_created',
            'admin_role_updated',
            'admin_toggled',
            'admin_password_reset',
        ];
        if (!in_array($eventType, $allowedEvents, true)) {
            $eventType = 'all';
        }
        $where = ['organization_id = ?', 'email_normalized = ?'];
        $params = ['admin', 'admin'];
        if ($eventType !== 'all') {
            $where[] = 'event_type = ?';
            $params[] = $eventType;
        }
        if ($q !== '') {
            $where[] = '(actor_email LIKE ? OR details_json LIKE ? OR event_type LIKE ?)';
            $like = '%' . $q . '%';
            array_push($params, $like, $like, $like);
        }
        $whereSql = implode(' AND ', $where);
        $st = $pdo->prepare(
            'SELECT id, actor_email, event_type, details_json, created_at
             FROM subscriber_activity_log
             WHERE ' . $whereSql . '
             ORDER BY created_at DESC
             LIMIT ?',
        );
        $params[] = $limit;
        $st->execute($params);
        activation_json(200, ['items' => $st->fetchAll(PDO::FETCH_ASSOC)]);
    }

    if ($method === 'GET' && $path === '/admin/me') {
        $admin = activation_require_admin($config, $pdo);
        activation_json(200, [
            'email' => (string) ($admin['email'] ?? ''),
            'acl' => (string) ($admin['acl'] ?? 'approver'),
            'adminRole' => activation_admin_role($admin),
            'legacy' => !empty($admin['legacy']),
            'sub' => (string) ($admin['sub'] ?? ''),
        ]);
    }

    if ($method === 'POST' && $path === '/admin/me/password') {
        $admin = activation_require_admin($config, $pdo);
        $sub = (string) ($admin['sub'] ?? '');
        if ($sub === '' || $sub === 'legacy-env') {
            activation_json(403, ['error' => 'legacy_no_password_change']);
        }
        $body = activation_json_body();
        $cur = (string) ($body['currentPassword'] ?? '');
        $neu = (string) ($body['newPassword'] ?? '');
        if (strlen($cur) < 4 || strlen($neu) < 8) {
            activation_json(400, ['error' => 'validation']);
        }
        $st = $pdo->prepare('SELECT * FROM admins WHERE id = ?');
        $st->execute([$sub]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row || !password_verify($cur, (string) $row['password_hash'])) {
            activation_json(401, ['error' => 'unauthorized']);
        }
        $hash = password_hash($neu, PASSWORD_BCRYPT, ['cost' => 10]);
        $up = $pdo->prepare('UPDATE admins SET password_hash = ? WHERE id = ?');
        $up->execute([$hash, $sub]);
        activation_json(200, ['ok' => true]);
    }

    if ($method === 'GET' && $path === '/admin/subscribers/detail') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'read');
        $organizationId = trim((string) ($_GET['organizationId'] ?? ''));
        $email = strtolower(trim((string) ($_GET['email'] ?? '')));
        if ($organizationId === '' || strpos($email, '@') === false) {
            activation_json(400, ['error' => 'validation']);
        }

        $stMain = $pdo->prepare(
            "SELECT id, organization_id, full_name, email, phone, dial_code, requested_at, status, reviewed_at, reviewed_by, issued_activation_key
             FROM signup_requests
             WHERE trim(organization_id) = trim(?) AND lower(trim(email)) = ?
             ORDER BY requested_at DESC
             LIMIT 1",
        );
        $stMain->execute([$organizationId, $email]);
        $signup = $stMain->fetch(PDO::FETCH_ASSOC) ?: null;

        $stHist = $pdo->prepare(
            "SELECT id, requested_at, status, reviewed_at, reviewed_by, issued_activation_key
             FROM signup_requests
             WHERE trim(organization_id) = trim(?) AND lower(trim(email)) = ?
             ORDER BY requested_at DESC
             LIMIT 30",
        );
        $stHist->execute([$organizationId, $email]);
        $history = $stHist->fetchAll(PDO::FETCH_ASSOC);

        $stEvt = $pdo->prepare(
            'SELECT id, actor_email, event_type, details_json, created_at
             FROM subscriber_activity_log
             WHERE trim(organization_id) = trim(?) AND email_normalized = ?
             ORDER BY created_at DESC
             LIMIT 50',
        );
        $stEvt->execute([$organizationId, $email]);
        $events = $stEvt->fetchAll(PDO::FETCH_ASSOC);

        $stDev = $pdo->prepare(
            'SELECT id, installation_id, device_fingerprint, computer_name, os_user, os_name, last_seen_at, revoked_at
             FROM subscriber_devices
             WHERE trim(organization_id) = trim(?) AND email_normalized = ?
             ORDER BY CASE WHEN revoked_at IS NULL THEN 0 ELSE 1 END, last_seen_at DESC',
        );
        $stDev->execute([$organizationId, $email]);
        $devices = $stDev->fetchAll(PDO::FETCH_ASSOC);

        $stLic = $pdo->prepare(
            'SELECT organization_id, email_normalized, trial_end_at, subscription_annual_until, legacy_activated, updated_at, admin_valid_until, access_suspended
             FROM license_snapshots WHERE trim(organization_id) = trim(?) AND email_normalized = ?',
        );
        $stLic->execute([$organizationId, $email]);
        $lic = $stLic->fetch(PDO::FETCH_ASSOC) ?: null;

        $effectiveUntil = null;
        if ($lic && empty($lic['access_suspended'])) {
            $effectiveUntil = activation_latest_iso_date(
                isset($lic['admin_valid_until']) ? (string) $lic['admin_valid_until'] : null,
                isset($lic['subscription_annual_until']) ? (string) $lic['subscription_annual_until'] : null,
            );
        }

        $slots = activation_redeem_slot_stats($pdo, $organizationId, $email);

        activation_json(200, [
            'organizationId' => $organizationId,
            'email' => $email,
            'signup' => $signup,
            'license' => $lic,
            'effectiveAnnualUntil' => $effectiveUntil,
            'daysRemaining' => activation_days_remaining($effectiveUntil),
            'history' => $history,
            'events' => $events,
            'devices' => $devices,
            'activationSlots' => [
                'used' => $slots['used'],
                'max' => $slots['max'],
                'signupRequestId' => $slots['signupRequestId'],
            ],
        ]);
    }

    if ($method === 'GET' && $path === '/admin/devices/list') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'read');
        $limit = (int) ($_GET['limit'] ?? 50);
        if ($limit < 1) {
            $limit = 50;
        }
        if ($limit > 200) {
            $limit = 200;
        }
        $offset = (int) ($_GET['offset'] ?? 0);
        if ($offset < 0) {
            $offset = 0;
        }
        $q = trim((string) ($_GET['q'] ?? ''));
        $status = strtolower(trim((string) ($_GET['status'] ?? 'all')));
        $sortBy = strtolower(trim((string) ($_GET['sortBy'] ?? 'last_seen_at')));
        $sortDir = strtolower(trim((string) ($_GET['sortDir'] ?? 'desc')));
        if (!in_array($status, ['all', 'active', 'revoked'], true)) {
            $status = 'all';
        }
        if (!in_array($sortBy, ['organization_id', 'email', 'computer_name', 'os_name', 'last_seen_at', 'revoked_at'], true)) {
            $sortBy = 'last_seen_at';
        }
        if (!in_array($sortDir, ['asc', 'desc'], true)) {
            $sortDir = 'desc';
        }

        $where = [];
        $params = [];
        if ($status === 'active') {
            $where[] = 'sd.revoked_at IS NULL';
        } elseif ($status === 'revoked') {
            $where[] = 'sd.revoked_at IS NOT NULL';
        }
        if ($q !== '') {
            $where[] = '(lower(trim(sd.organization_id)) LIKE ? OR lower(sd.email_normalized) LIKE ? OR lower(COALESCE(sd.computer_name, \'\')) LIKE ? OR lower(COALESCE(sd.os_user, \'\')) LIKE ? OR lower(COALESCE(sd.os_name, \'\')) LIKE ?)';
            $needle = '%' . strtolower($q) . '%';
            $params[] = $needle;
            $params[] = $needle;
            $params[] = $needle;
            $params[] = $needle;
            $params[] = $needle;
        }
        $whereSql = $where ? (' WHERE ' . implode(' AND ', $where)) : '';

        $stCount = $pdo->prepare("SELECT COUNT(*) AS c FROM subscriber_devices sd$whereSql");
        $stCount->execute($params);
        $total = (int) ($stCount->fetch(PDO::FETCH_ASSOC)['c'] ?? 0);

        $sortExprMap = [
            'organization_id' => 'trim(sd.organization_id)',
            'email' => 'sd.email_normalized',
            'computer_name' => 'COALESCE(sd.computer_name, \'\')',
            'os_name' => 'COALESCE(sd.os_name, \'\')',
            'last_seen_at' => 'COALESCE(sd.last_seen_at, \'\')',
            'revoked_at' => 'COALESCE(sd.revoked_at, \'\')',
        ];
        $sortExpr = $sortExprMap[$sortBy] ?? $sortExprMap['last_seen_at'];
        $sortSql = $sortExpr . ' ' . strtoupper($sortDir);

        $st = $pdo->prepare(
            "SELECT
                sd.id,
                trim(sd.organization_id) AS organization_id,
                sd.email_normalized AS email,
                sd.installation_id,
                sd.device_fingerprint,
                sd.computer_name,
                sd.os_user,
                sd.os_name,
                sd.last_seen_at,
                sd.revoked_at,
                COALESCE(ls.access_suspended, 0) AS access_suspended
             FROM subscriber_devices sd
             LEFT JOIN license_snapshots ls
               ON trim(ls.organization_id) = trim(sd.organization_id)
              AND ls.email_normalized = sd.email_normalized
             $whereSql
             ORDER BY CASE WHEN sd.revoked_at IS NULL THEN 0 ELSE 1 END, $sortSql
             LIMIT ? OFFSET ?",
        );
        $bindIdx = 1;
        foreach ($params as $p) {
            $st->bindValue($bindIdx, $p, PDO::PARAM_STR);
            $bindIdx++;
        }
        $st->bindValue($bindIdx, $limit, PDO::PARAM_INT);
        $st->bindValue($bindIdx + 1, $offset, PDO::PARAM_INT);
        $st->execute();
        $items = $st->fetchAll(PDO::FETCH_ASSOC);
        activation_json(200, [
            'ok' => true,
            'items' => $items,
            'total' => $total,
            'limit' => $limit,
            'offset' => $offset,
            'status' => $status,
            'q' => $q,
            'sortBy' => $sortBy,
            'sortDir' => $sortDir,
        ]);
    }

    if ($method === 'POST' && $path === '/admin/device-code/resolve') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'read');
        $body = activation_json_body();
        $deviceLinkCode = trim((string) ($body['deviceLinkCode'] ?? ''));
        if ($deviceLinkCode === '') {
            activation_json(400, ['error' => 'validation']);
        }
        $resolved = activation_resolve_signup_from_device_code($pdo, $deviceLinkCode);
        if (empty($resolved['ok'])) {
            $err = (string) ($resolved['error'] ?? 'server');
            if ($err === 'invalid_device_code') {
                activation_json(400, ['error' => 'invalid_device_code']);
            }
            if ($err === 'not_found') {
                $claim = activation_resolve_claim_from_device_code($pdo, $deviceLinkCode);
                if (!empty($claim['ok'])) {
                    activation_json(200, [
                        'ok' => true,
                        'installationId' => $claim['installationId'] ?? null,
                        'organizationId' => (string) ($claim['organizationId'] ?? ''),
                        'email' => strtolower(trim((string) ($claim['email'] ?? ''))),
                        'signupRequestId' => (string) ($claim['signupRequestId'] ?? ''),
                        'source' => 'device_link_claim',
                    ]);
                }
                activation_json(404, [
                    'error' => 'not_found',
                    'installationId' => $resolved['installationId'] ?? null,
                ]);
            }
            activation_json(500, ['error' => 'server']);
        }
        $sr = $resolved['signup'];
        activation_json(200, [
            'ok' => true,
            'installationId' => $resolved['installationId'] ?? null,
            'organizationId' => (string) ($sr['organization_id'] ?? ''),
            'email' => strtolower(trim((string) ($sr['email'] ?? ''))),
            'fullName' => (string) ($sr['full_name'] ?? ''),
            'signupRequestId' => (string) ($sr['id'] ?? ''),
        ]);
    }

    if ($method === 'POST' && $path === '/admin/device-code/activate') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'approve_reject');
        $body = activation_json_body();
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        $deviceLinkCode = trim((string) ($body['deviceLinkCode'] ?? ''));
        $signupRequestId = trim((string) ($body['signupRequestId'] ?? ''));
        $resolvedEmail = strtolower(trim((string) ($body['resolvedEmail'] ?? '')));
        $effectiveEmail = strpos($email, '@') !== false ? $email : $resolvedEmail;
        if ($deviceLinkCode === '') {
            activation_json(400, ['error' => 'validation']);
        }
        $installationId = activation_device_link_code_to_installation_id($deviceLinkCode);
        if ($installationId === null) {
            activation_json(400, ['error' => 'invalid_device_code']);
        }
        if ($signupRequestId === '' && strpos($effectiveEmail, '@') === false) {
            activation_json(400, ['error' => 'missing_email']);
        }
        try {
            $pdo->beginTransaction();
            if ($signupRequestId !== '' && $organizationId !== '') {
                $st = $pdo->prepare(
                    "SELECT * FROM signup_requests
                     WHERE id = ? AND trim(organization_id) = trim(?) AND status = 'approved'
                     LIMIT 1",
                );
                $st->execute([$signupRequestId, $organizationId]);
            } else {
                if ($organizationId !== '') {
                    $st = $pdo->prepare(
                        "SELECT * FROM signup_requests
                         WHERE trim(organization_id) = trim(?) AND lower(trim(email)) = ? AND status = 'approved'
                         ORDER BY COALESCE(reviewed_at, requested_at) DESC
                         LIMIT 1",
                    );
                    $st->execute([$organizationId, $effectiveEmail]);
                } else {
                    $st = $pdo->prepare(
                        "SELECT * FROM signup_requests
                         WHERE lower(trim(email)) = ? AND status = 'approved'
                         ORDER BY COALESCE(reviewed_at, requested_at) DESC",
                    );
                    $st->execute([$effectiveEmail]);
                }
            }
            $matched = null;
            if ($organizationId !== '' || $signupRequestId !== '') {
                $matched = $st->fetch(PDO::FETCH_ASSOC);
            } else {
                $rows = $st->fetchAll(PDO::FETCH_ASSOC);
                if (count($rows) > 1) {
                    if ($pdo->inTransaction()) {
                        $pdo->rollBack();
                    }
                    activation_json(409, ['error' => 'ambiguous_organization']);
                }
                $matched = $rows[0] ?? null;
            }
            if (!$matched) {
                if ($pdo->inTransaction()) {
                    $pdo->rollBack();
                }
                activation_json(404, ['error' => 'not_found']);
            }
            $organizationId = trim((string) ($matched['organization_id'] ?? $organizationId));
            $matchedEmail = strtolower(trim((string) ($matched['email'] ?? '')));
            if (strpos($effectiveEmail, '@') === false) {
                $effectiveEmail = $matchedEmail;
            }
            $fromEmail = $resolvedEmail !== '' ? $resolvedEmail : $matchedEmail;
            if ($fromEmail !== '' && $fromEmail !== $effectiveEmail) {
                $up1 = $pdo->prepare('UPDATE signup_requests SET email = ? WHERE id = ?');
                $up1->execute([$effectiveEmail, (string) ($matched['id'] ?? '')]);

                $up2 = $pdo->prepare(
                    'UPDATE license_snapshots
                     SET email_normalized = ?
                     WHERE trim(organization_id) = trim(?) AND email_normalized = ?',
                );
                $up2->execute([$effectiveEmail, $organizationId, $fromEmail]);

                $up3 = $pdo->prepare(
                    'UPDATE subscriber_devices
                     SET email_normalized = ?
                     WHERE trim(organization_id) = trim(?) AND email_normalized = ?',
                );
                $up3->execute([$effectiveEmail, $organizationId, $fromEmail]);

                $up4 = $pdo->prepare(
                    'UPDATE subscriber_activity_log
                     SET email_normalized = ?
                     WHERE trim(organization_id) = trim(?) AND email_normalized = ?',
                );
                $up4->execute([$effectiveEmail, $organizationId, $fromEmail]);

                $matched['email'] = $effectiveEmail;
            }
            [$statusCode, $payload] = activation_redeem_for_installation($pdo, $matched, $installationId);
            if ($statusCode !== 200) {
                if ($pdo->inTransaction()) {
                    $pdo->rollBack();
                }
                activation_json($statusCode, $payload);
            }
            $pdo->commit();
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            error_log('[activation] device-code/activate: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }
        activation_log_subscriber_event($pdo, $organizationId, $effectiveEmail, $admin, 'device_activated_by_admin', [
            'installationId' => $installationId,
            'signupRequestId' => (string) ($matched['id'] ?? ''),
        ]);
        activation_json(200, [
            'ok' => true,
            'organizationId' => $organizationId,
            'email' => $effectiveEmail,
            'installationId' => $installationId,
        ]);
    }

    if ($method === 'POST' && $path === '/admin/subscribers/device/revoke') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'delete');
        $body = activation_json_body();
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        $deviceId = trim((string) ($body['deviceId'] ?? ''));
        if ($organizationId === '' || strpos($email, '@') === false || $deviceId === '') {
            activation_json(400, ['error' => 'validation']);
        }
        try {
            $stInst = $pdo->prepare(
                'SELECT installation_id FROM subscriber_devices
                 WHERE id = ? AND trim(organization_id) = trim(?) AND email_normalized = ?',
            );
            $stInst->execute([$deviceId, $organizationId, $email]);
            $instRow = $stInst->fetch(PDO::FETCH_ASSOC);
            if (!$instRow) {
                activation_json(404, ['error' => 'not_found']);
            }
            $installationId = trim((string) ($instRow['installation_id'] ?? ''));
            $up = $pdo->prepare(
                'UPDATE subscriber_devices
                 SET revoked_at = ?
                 WHERE id = ? AND trim(organization_id) = trim(?) AND email_normalized = ?',
            );
            $up->execute([activation_now_iso(), $deviceId, $organizationId, $email]);
            if ($up->rowCount() < 1) {
                activation_json(404, ['error' => 'not_found']);
            }
            if ($installationId !== '') {
                $dr = $pdo->prepare('DELETE FROM activation_redeems WHERE installation_id = ?');
                $dr->execute([$installationId]);
            }
            activation_log_subscriber_event($pdo, $organizationId, $email, $admin, 'device_revoked', [
                'deviceId' => $deviceId,
            ]);
            activation_json(200, ['ok' => true]);
        } catch (Throwable $e) {
            error_log('[activation] device/revoke: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }
    }

    if ($method === 'POST' && $path === '/admin/subscribers/profile') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'extend');
        $body = activation_json_body();
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        $fullName = trim((string) ($body['fullName'] ?? ''));
        $dialCode = trim((string) ($body['dialCode'] ?? ''));
        $phone = preg_replace('/\D/', '', (string) ($body['phone'] ?? '')) ?? '';
        if (
            $organizationId === '' ||
            strpos($email, '@') === false ||
            strlen($fullName) < 2 ||
            strlen($phone) < 6 ||
            $dialCode === ''
        ) {
            activation_json(400, ['error' => 'validation']);
        }
        try {
            $up = $pdo->prepare(
                'UPDATE signup_requests
                 SET full_name = ?, phone = ?, dial_code = ?
                 WHERE trim(organization_id) = trim(?) AND lower(trim(email)) = ?',
            );
            $up->execute([$fullName, $phone, $dialCode, $organizationId, $email]);
            activation_log_subscriber_event($pdo, $organizationId, $email, $admin, 'profile_updated', [
                'fullName' => $fullName,
                'dialCode' => $dialCode,
                'phone' => $phone,
                'updatedRows' => $up->rowCount(),
            ]);
            activation_json(200, ['ok' => true, 'updated' => $up->rowCount()]);
        } catch (Throwable $e) {
            error_log('[activation] subscribers/profile: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }
    }

    if ($method === 'POST' && $path === '/admin/subscribers/change-email') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'extend');
        $body = activation_json_body();
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        $currentEmail = strtolower(trim((string) ($body['currentEmail'] ?? '')));
        $newEmail = strtolower(trim((string) ($body['newEmail'] ?? '')));
        if (
            $organizationId === '' ||
            strpos($currentEmail, '@') === false ||
            strpos($newEmail, '@') === false
        ) {
            activation_json(400, ['error' => 'validation']);
        }
        if ($currentEmail === $newEmail) {
            activation_json(200, ['ok' => true, 'updated' => 0]);
        }
        try {
            $pdo->beginTransaction();
            $up1 = $pdo->prepare(
                'UPDATE signup_requests
                 SET email = ?
                 WHERE trim(organization_id) = trim(?) AND lower(trim(email)) = ?',
            );
            $up1->execute([$newEmail, $organizationId, $currentEmail]);

            $up2 = $pdo->prepare(
                'UPDATE license_snapshots
                 SET email_normalized = ?
                 WHERE trim(organization_id) = trim(?) AND email_normalized = ?',
            );
            $up2->execute([$newEmail, $organizationId, $currentEmail]);

            $up3 = $pdo->prepare(
                'UPDATE subscriber_devices
                 SET email_normalized = ?
                 WHERE trim(organization_id) = trim(?) AND email_normalized = ?',
            );
            $up3->execute([$newEmail, $organizationId, $currentEmail]);

            $up4 = $pdo->prepare(
                'UPDATE subscriber_activity_log
                 SET email_normalized = ?
                 WHERE trim(organization_id) = trim(?) AND email_normalized = ?',
            );
            $up4->execute([$newEmail, $organizationId, $currentEmail]);
            activation_log_subscriber_event($pdo, $organizationId, $newEmail, $admin, 'subscriber_email_changed', [
                'from' => $currentEmail,
                'to' => $newEmail,
                'signupUpdated' => $up1->rowCount(),
            ]);
            $pdo->commit();
            activation_json(200, [
                'ok' => true,
                'updated' => $up1->rowCount(),
            ]);
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            error_log('[activation] subscribers/change-email: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }
    }

    if ($method === 'POST' && $path === '/admin/subscribers/password') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'password');
        $body = activation_json_body();
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        $newPassword = (string) ($body['newPassword'] ?? '');
        if ($organizationId === '' || strpos($email, '@') === false || strlen($newPassword) < 8) {
            activation_json(400, ['error' => 'validation']);
        }
        try {
            $st = $pdo->prepare(
                'SELECT id FROM signup_requests
                 WHERE trim(organization_id) = trim(?) AND lower(trim(email)) = ?
                 ORDER BY requested_at DESC
                 LIMIT 1',
            );
            $st->execute([$organizationId, $email]);
            $row = $st->fetch(PDO::FETCH_ASSOC);
            if (!$row) {
                activation_json(404, ['error' => 'not_found']);
            }
            $hash = password_hash($newPassword, PASSWORD_BCRYPT, ['cost' => 10]);
            $up = $pdo->prepare(
                'UPDATE signup_requests
                 SET password_hash = ?
                 WHERE trim(organization_id) = trim(?) AND lower(trim(email)) = ?',
            );
            $up->execute([$hash, $organizationId, $email]);
            activation_log_subscriber_event($pdo, $organizationId, $email, $admin, 'password_changed', [
                'updatedRows' => $up->rowCount(),
            ]);
            activation_json(200, ['ok' => true, 'updated' => $up->rowCount()]);
        } catch (Throwable $e) {
            error_log('[activation] subscribers/password: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }
    }

    if ($method === 'POST' && $path === '/admin/activation/issue-code') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'approve_reject');
        $body = activation_json_body();
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        $signupRequestId = trim((string) ($body['signupRequestId'] ?? ''));
        if ($organizationId === '' || strpos($email, '@') === false) {
            activation_json(400, ['error' => 'validation']);
        }

        $reviewer = activation_admin_reviewer_label($admin);
        $now = activation_now_iso();

        $targetRow = null;
        if ($signupRequestId !== '') {
            $st = $pdo->prepare('SELECT * FROM signup_requests WHERE id = ?');
            $st->execute([$signupRequestId]);
            $targetRow = $st->fetch(PDO::FETCH_ASSOC);
            if (
                !$targetRow
                || trim((string) ($targetRow['organization_id'] ?? '')) !== $organizationId
                || strtolower(trim((string) ($targetRow['email'] ?? ''))) !== $email
            ) {
                activation_json(404, ['error' => 'not_found']);
            }
        } else {
            $st = $pdo->prepare(
                "SELECT * FROM signup_requests
                 WHERE trim(organization_id) = trim(?) AND lower(trim(email)) = ?
                 ORDER BY requested_at DESC
                 LIMIT 1",
            );
            $st->execute([$organizationId, $email]);
            $targetRow = $st->fetch(PDO::FETCH_ASSOC) ?: null;
        }

        $fullNameIns = trim((string) ($body['fullName'] ?? ''));
        $dialCodeIns = trim((string) ($body['dialCode'] ?? '')) ?: '+970';
        $phoneIns = preg_replace('/\D/', '', (string) ($body['phone'] ?? ''));
        if ($targetRow === null) {
            if (strlen($fullNameIns) < 2 || strlen($phoneIns) < 6) {
                activation_json(400, ['error' => 'validation', 'hint' => 'missing_profile_for_new_subscriber']);
            }
        }

        try {
            $pdo->beginTransaction();
            if ($targetRow !== null) {
                $targetId = (string) $targetRow['id'];
                activation_clear_redeems_for_signup($pdo, $targetId);
                $u1 = $pdo->prepare(
                    "UPDATE signup_requests SET issued_activation_key = NULL
                     WHERE organization_id = ? AND lower(trim(email)) = ? AND id != ?
                       AND issued_activation_key IS NOT NULL",
                );
                $u1->execute([$organizationId, $email, $targetId]);
                $u2 = $pdo->prepare(
                    "UPDATE signup_requests SET
                       status = 'approved',
                       reviewed_at = ?,
                       reviewed_by = ?,
                       issued_activation_key = NULL
                     WHERE id = ?",
                );
                $u2->execute([$now, $reviewer, $targetId]);
            } else {
                $targetId = activation_uuid();
                $hash = password_hash(bin2hex(random_bytes(24)), PASSWORD_BCRYPT, ['cost' => 10]);
                $ins = $pdo->prepare(
                    "INSERT INTO signup_requests (
                      id, organization_id, full_name, email, phone, dial_code, password_hash,
                      requested_at, status, reviewed_at, reviewed_by, issued_activation_key
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'approved', ?, ?, NULL)",
                );
                $ins->execute([
                    $targetId,
                    $organizationId,
                    $fullNameIns,
                    $email,
                    $phoneIns,
                    $dialCodeIns,
                    $hash,
                    $now,
                    $now,
                    $reviewer,
                ]);
            }
            $upLs = $pdo->prepare(
                'INSERT INTO license_snapshots (
                    organization_id, email_normalized, trial_end_at, subscription_annual_until, legacy_activated, updated_at, admin_valid_until, last_activation_code, access_suspended
                ) VALUES (?, ?, NULL, NULL, 0, ?, NULL, NULL, 0)
                ON CONFLICT(organization_id, email_normalized) DO UPDATE SET
                    last_activation_code = NULL,
                    updated_at = excluded.updated_at',
            );
            $upLs->execute([$organizationId, $email, $now]);
            activation_log_subscriber_event($pdo, $organizationId, $email, $admin, 'subscriber_devices_reset', [
                'signupRequestId' => $targetId,
            ]);
            $pdo->commit();
            activation_json(200, [
                'ok' => true,
                'signupRequestId' => $targetId,
            ]);
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            error_log('[activation] issue-code: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }
    }

    if ($method === 'GET' && $path === '/admin/signups/pending') {
        activation_require_admin($config, $pdo);
        $st = $pdo->query(
            "SELECT id, organization_id, full_name, email, phone, dial_code, requested_at
             FROM signup_requests WHERE status = 'pending'
             ORDER BY requested_at DESC",
        );
        $items = $st->fetchAll(PDO::FETCH_ASSOC);
        activation_json(200, ['items' => $items]);
    }

    if ($method === 'GET' && $path === '/admin/signups/stats') {
        activation_require_admin($config, $pdo);
        activation_ensure_signup_schema($pdo);
        $out = ['total' => 0, 'pending' => 0, 'approved' => 0, 'rejected' => 0];
        $st = $pdo->query('SELECT status, COUNT(*) AS c FROM signup_requests GROUP BY status');
        foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $r) {
            $c = (int) $r['c'];
            $out['total'] += $c;
            $s = (string) $r['status'];
            if (array_key_exists($s, $out)) {
                $out[$s] = $c;
            }
        }
        activation_json(200, $out);
    }

    if ($method === 'GET' && $path === '/admin/signups/archive') {
        activation_require_admin($config, $pdo);
        activation_ensure_signup_schema($pdo);
        $status = strtolower(trim((string) ($_GET['status'] ?? 'all')));
        if (!in_array($status, ['all', 'pending', 'approved', 'rejected'], true)) {
            $status = 'all';
        }
        $q = trim((string) ($_GET['q'] ?? ''));
        $limit = (int) ($_GET['limit'] ?? 50);
        if ($limit < 1) {
            $limit = 50;
        }
        if ($limit > 2000) {
            $limit = 2000;
        }
        $offset = (int) ($_GET['offset'] ?? 0);
        if ($offset < 0) {
            $offset = 0;
        }

        $where = ['1=1'];
        $params = [];
        if ($status !== 'all') {
            $where[] = 'sr.status = ?';
            $params[] = $status;
        }
        if ($q !== '') {
            $like = '%' . $q . '%';
            $where[] = '(sr.full_name LIKE ? OR sr.email LIKE ? OR sr.phone LIKE ? OR sr.organization_id LIKE ? OR sr.id LIKE ?
                OR sr.reviewed_by LIKE ? OR sr.issued_activation_key LIKE ?)';
            array_push($params, $like, $like, $like, $like, $like, $like, $like);
        }
        $whereSql = implode(' AND ', $where);

        try {
            $cntSt = $pdo->prepare("SELECT COUNT(*) AS c FROM signup_requests sr WHERE $whereSql");
            $cntSt->execute($params);
            $total = (int) ($cntSt->fetch(PDO::FETCH_ASSOC)['c'] ?? 0);

            $sql = "SELECT sr.id, sr.organization_id, sr.full_name, sr.email, sr.phone, sr.dial_code, sr.requested_at, sr.status, sr.reviewed_at, sr.reviewed_by,
                sr.issued_activation_key, sr.email_verified,
                ls.trial_end_at AS snapshot_trial_end_at,
                ls.subscription_annual_until AS snapshot_subscription_annual_until,
                ls.admin_valid_until AS snapshot_admin_valid_until,
                ls.access_suspended AS snapshot_access_suspended,
                ls.legacy_activated AS snapshot_legacy_activated,
                ls.updated_at AS snapshot_updated_at,
                ls.distributor_cloud_until AS snapshot_distributor_cloud_until,
                ls.max_distributor_seats AS snapshot_max_distributor_seats
             FROM signup_requests sr
             LEFT JOIN license_snapshots ls ON trim(sr.organization_id) = trim(ls.organization_id) AND lower(trim(sr.email)) = ls.email_normalized
             WHERE $whereSql
             ORDER BY sr.requested_at DESC LIMIT $limit OFFSET $offset";
            $st = $pdo->prepare($sql);
            $st->execute($params);
            $items = $st->fetchAll(PDO::FETCH_ASSOC);
            activation_enrich_signups_voucher_links($pdo, $items);
            foreach ($items as &$row) {
                $row['email_verified'] = !empty($row['email_verified']);
                $row['dial_code'] = activation_normalize_dial_code((string) ($row['dial_code'] ?? ''));
                $row['trial_days_remaining'] = activation_days_remaining($row['snapshot_trial_end_at'] ?? null);
                $row['subscription_is_legacy'] = !empty($row['snapshot_legacy_activated']);
                $row['access_suspended'] = !empty($row['snapshot_access_suspended']);
                if ($row['subscription_is_legacy']) {
                    $row['subscription_days_remaining'] = null;
                    $row['subscription_effective_until'] = null;
                } else {
                    $subUntil = isset($row['snapshot_subscription_annual_until'])
                        ? trim((string) $row['snapshot_subscription_annual_until'])
                        : '';
                    $adminUntil = isset($row['snapshot_admin_valid_until'])
                        ? trim((string) $row['snapshot_admin_valid_until'])
                        : '';
                    $effectiveUntil = $row['access_suspended']
                        ? null
                        : activation_latest_iso_date(
                            $adminUntil !== '' ? $adminUntil : null,
                            $subUntil !== '' ? $subUntil : null,
                        );
                    $row['subscription_effective_until'] = $effectiveUntil;
                    $row['subscription_days_remaining'] = activation_days_remaining($effectiveUntil);
                }
                $row['license_snapshot_at'] = $row['snapshot_updated_at'] ?? null;
                $distUntil = isset($row['snapshot_distributor_cloud_until'])
                    ? trim((string) $row['snapshot_distributor_cloud_until'])
                    : '';
                $row['distributorCloudUntil'] = $distUntil !== '' ? $distUntil : null;
                $row['distributorCloudActive'] = $distUntil !== ''
                    && strtotime($distUntil) !== false
                    && strtotime($distUntil) >= time();
                $seatsRaw = $row['snapshot_max_distributor_seats'] ?? null;
                $row['maxDistributorSeats'] = ($seatsRaw === null || $seatsRaw === '')
                    ? null
                    : max(0, (int) $seatsRaw);
                $row['usedDistributorSeats'] = distributor_license_count_distributor_seats(
                    $pdo,
                    (string) ($row['organization_id'] ?? ''),
                );
                unset(
                    $row['snapshot_trial_end_at'],
                    $row['snapshot_subscription_annual_until'],
                    $row['snapshot_admin_valid_until'],
                    $row['snapshot_access_suspended'],
                    $row['snapshot_legacy_activated'],
                    $row['snapshot_updated_at'],
                    $row['snapshot_distributor_cloud_until'],
                    $row['snapshot_max_distributor_seats'],
                );
            }
            unset($row);
            activation_json(200, [
                'ok' => true,
                'items' => $items,
                'total' => $total,
                'limit' => $limit,
                'offset' => $offset,
            ]);
        } catch (Throwable $e) {
            error_log('[activation] signups/archive: ' . $e->getMessage());
            activation_json(500, ['ok' => false, 'error' => 'server']);
        }
    }

    if ($method === 'GET' && $path === '/admin/signups/voucher-activity') {
        activation_require_admin($config, $pdo);
        $organizationId = trim((string) ($_GET['organizationId'] ?? ''));
        $email = strtolower(trim((string) ($_GET['email'] ?? '')));
        if ($organizationId === '' || strpos($email, '@') === false) {
            activation_json(400, ['error' => 'validation']);
        }
        try {
            $activity = activation_subscriber_voucher_activity($pdo, $organizationId, $email);
            activation_json(200, array_merge(['ok' => true], $activity));
        } catch (Throwable $e) {
            error_log('[activation] signups/voucher-activity: ' . $e->getMessage());
            activation_json(500, ['ok' => false, 'error' => 'server']);
        }
    }

    if ($method === 'GET' && $path === '/admin/signups/export') {
        activation_require_admin($config, $pdo);
        activation_ensure_signup_schema($pdo);
        $status = strtolower(trim((string) ($_GET['status'] ?? 'all')));
        if (!in_array($status, ['all', 'pending', 'approved', 'rejected'], true)) {
            $status = 'all';
        }
        $q = trim((string) ($_GET['q'] ?? ''));

        $where = ['1=1'];
        $params = [];
        if ($status !== 'all') {
            $where[] = 'sr.status = ?';
            $params[] = $status;
        }
        if ($q !== '') {
            $like = '%' . $q . '%';
            $where[] = '(sr.full_name LIKE ? OR sr.email LIKE ? OR sr.phone LIKE ? OR sr.organization_id LIKE ? OR sr.id LIKE ?
                OR sr.reviewed_by LIKE ? OR sr.issued_activation_key LIKE ?)';
            array_push($params, $like, $like, $like, $like, $like, $like, $like);
        }
        $whereSql = implode(' AND ', $where);

        $st = $pdo->prepare(
            "SELECT sr.id, sr.organization_id, sr.full_name, sr.email, sr.phone, sr.dial_code, sr.requested_at, sr.status, sr.reviewed_at, sr.reviewed_by,
                sr.email_verified,
                ls.trial_end_at AS snapshot_trial_end_at,
                ls.subscription_annual_until AS snapshot_subscription_annual_until,
                ls.admin_valid_until AS snapshot_admin_valid_until,
                ls.access_suspended AS snapshot_access_suspended,
                ls.legacy_activated AS snapshot_legacy_activated
             FROM signup_requests sr
             LEFT JOIN license_snapshots ls ON trim(sr.organization_id) = trim(ls.organization_id) AND lower(trim(sr.email)) = ls.email_normalized
             WHERE $whereSql
             ORDER BY sr.requested_at DESC",
        );
        $st->execute($params);
        $rows = $st->fetchAll(PDO::FETCH_ASSOC);
        activation_enrich_signups_voucher_links($pdo, $rows);

        $csv = "full_name,email,dial_code,phone,status,email_verified,has_voucher,voucher_code,voucher_status,requested_at,organization_id,reviewed_at,subscription_days_remaining,subscription_effective_until,access_suspended,trial_days_remaining,subscription_is_legacy\n";
        foreach ($rows as $r) {
            $trialDays = activation_days_remaining($r['snapshot_trial_end_at'] ?? null);
            $legacy = !empty($r['snapshot_legacy_activated']);
            $suspended = !empty($r['snapshot_access_suspended']);
            if ($legacy) {
                $subDays = '';
                $effectiveUntil = '';
            } else {
                $subUntil = isset($r['snapshot_subscription_annual_until'])
                    ? trim((string) $r['snapshot_subscription_annual_until'])
                    : '';
                $adminUntil = isset($r['snapshot_admin_valid_until'])
                    ? trim((string) $r['snapshot_admin_valid_until'])
                    : '';
                $effectiveUntil = $suspended
                    ? ''
                    : (activation_latest_iso_date(
                        $adminUntil !== '' ? $adminUntil : null,
                        $subUntil !== '' ? $subUntil : null,
                    ) ?? '');
                $subDaysVal = activation_days_remaining($effectiveUntil !== '' ? $effectiveUntil : null);
                $subDays = $subDaysVal === null ? '' : (string) $subDaysVal;
            }
            $verified = !empty($r['email_verified']) ? '1' : '0';
            $line = [
                str_replace(["\r", "\n", ','], [' ', ' ', ' '], (string) ($r['full_name'] ?? '')),
                (string) ($r['email'] ?? ''),
                (string) ($r['dial_code'] ?? ''),
                (string) ($r['phone'] ?? ''),
                (string) ($r['status'] ?? ''),
                $verified,
                !empty($r['has_voucher']) ? '1' : '0',
                (string) ($r['voucher_code'] ?? ''),
                (string) ($r['voucher_status'] ?? ''),
                (string) ($r['requested_at'] ?? ''),
                (string) ($r['organization_id'] ?? ''),
                (string) ($r['reviewed_at'] ?? ''),
                $subDays,
                $effectiveUntil ?? '',
                $suspended ? '1' : '0',
                $trialDays !== null ? (string) $trialDays : '',
                $legacy ? '1' : '0',
            ];
            $csv .= implode(',', $line) . "\n";
        }
        activation_send(200, array_merge(activation_cors_headers(), [
            'Content-Type' => 'text/csv; charset=utf-8',
            'Content-Disposition' => 'attachment; filename="registered-' . date('Ymd-His') . '.csv"',
        ]), "\xEF\xBB\xBF" . $csv);
    }

    if ($method === 'POST' && preg_match('#^/admin/signups/([^/]+)/approve$#', $path, $m)) {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'approve_reject');
        $id = trim($m[1]);
        $st = $pdo->prepare('SELECT * FROM signup_requests WHERE id = ?');
        $st->execute([$id]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row || ($row['status'] ?? '') !== 'pending') {
            activation_json(404, ['error' => 'not_found']);
        }
        $reviewer = activation_admin_reviewer_label($admin);
        $email = strtolower(trim((string) ($row['email'] ?? '')));
        $organizationId = (string) $row['organization_id'];
        $now = activation_now_iso();
        try {
            $pdo->beginTransaction();
            activation_clear_redeems_for_signup($pdo, $id);
            $u1 = $pdo->prepare(
                "UPDATE signup_requests SET issued_activation_key = NULL
                 WHERE organization_id = ?
                   AND lower(trim(email)) = ?
                   AND id != ?
                   AND issued_activation_key IS NOT NULL",
            );
            $u1->execute([$organizationId, $email, $id]);
            $u2 = $pdo->prepare(
                "UPDATE signup_requests SET
                   status = 'approved',
                   reviewed_at = ?,
                   reviewed_by = ?,
                   issued_activation_key = NULL
                 WHERE id = ?",
            );
            $u2->execute([$now, $reviewer, $id]);
            $upLs = $pdo->prepare(
                'INSERT INTO license_snapshots (
                    organization_id, email_normalized, trial_end_at, subscription_annual_until, legacy_activated, updated_at, admin_valid_until, last_activation_code, access_suspended
                ) VALUES (?, ?, NULL, NULL, 0, ?, NULL, NULL, 0)
                ON CONFLICT(organization_id, email_normalized) DO UPDATE SET
                    last_activation_code = NULL,
                    updated_at = excluded.updated_at',
            );
            $upLs->execute([$organizationId, $email, $now]);
            activation_log_subscriber_event($pdo, $organizationId, $email, $admin, 'signup_approved', [
                'signupRequestId' => $id,
            ]);
            $pdo->commit();
            activation_json(200, ['ok' => true]);
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            error_log('[activation] approve: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }
    }

    if ($method === 'POST' && preg_match('#^/admin/signups/([^/]+)/reject$#', $path, $m)) {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'approve_reject');
        $id = trim($m[1]);
        $st = $pdo->prepare('SELECT * FROM signup_requests WHERE id = ?');
        $st->execute([$id]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row || ($row['status'] ?? '') !== 'pending') {
            activation_json(404, ['error' => 'not_found']);
        }
        $reviewer = activation_admin_reviewer_label($admin);
        $now = activation_now_iso();
        $up = $pdo->prepare(
            "UPDATE signup_requests SET status = 'rejected', reviewed_at = ?, reviewed_by = ?, issued_activation_key = NULL WHERE id = ?",
        );
        $up->execute([$now, $reviewer, $id]);
        $organizationId = (string) ($row['organization_id'] ?? '');
        $email = strtolower(trim((string) ($row['email'] ?? '')));
        activation_log_subscriber_event($pdo, $organizationId, $email, $admin, 'signup_rejected', [
            'signupRequestId' => $id,
        ]);
        activation_json(200, ['ok' => true]);
    }

    if ($method === 'GET' && $path === '/admin/licenses/snapshots') {
        activation_require_admin($config, $pdo);
        $limit = (int) ($_GET['limit'] ?? 100);
        if ($limit < 1) {
            $limit = 100;
        }
        if ($limit > 500) {
            $limit = 500;
        }
        $offset = (int) ($_GET['offset'] ?? 0);
        if ($offset < 0) {
            $offset = 0;
        }
        $q = trim((string) ($_GET['q'] ?? ''));
        $statusFilter = strtolower(trim((string) ($_GET['status'] ?? 'all')));
        $suspFilter = strtolower(trim((string) ($_GET['suspended'] ?? 'all')));
        $expiringDays = (int) ($_GET['expiringDays'] ?? -1);
        if (!in_array($statusFilter, ['all', 'pending', 'approved', 'rejected', 'device_only'], true)) {
            $statusFilter = 'all';
        }
        if (!in_array($suspFilter, ['all', 'yes', 'no'], true)) {
            $suspFilter = 'all';
        }
        if ($expiringDays < -2) {
            $expiringDays = -2;
        }
        if ($expiringDays > 3650) {
            $expiringDays = 3650;
        }
        /*
         * دمج في PHP بدل UNION الفرعي (أبسط وأقل عرضة لفشل SQLite/PDO على بعض الخوادم).
         * 1) signup_requests + لقطة ترخيص  2) لقطات بلا صف تسجيل مطابق
         */
        $sqlSignups = <<<'SQL'
SELECT
  trim(sr.organization_id) AS organization_id,
  lower(trim(sr.email)) AS email_normalized,
  sr.full_name AS signup_full_name,
  sr.status AS signup_status,
  sr.issued_activation_key AS issued_activation_key,
  ls.last_activation_code AS last_activation_code,
  ls.trial_end_at AS trial_end_at,
  ls.subscription_annual_until AS subscription_annual_until,
  ls.admin_valid_until AS admin_valid_until,
  COALESCE(ls.access_suspended, 0) AS access_suspended,
  COALESCE(ls.legacy_activated, 0) AS legacy_activated,
  COALESCE(ls.updated_at, sr.reviewed_at, sr.requested_at) AS updated_at
FROM signup_requests sr
LEFT JOIN license_snapshots ls
  ON trim(sr.organization_id) = trim(ls.organization_id)
 AND lower(trim(sr.email)) = ls.email_normalized
WHERE sr.status IN ('pending', 'approved', 'rejected')
SQL;
        $sqlDeviceOnly = <<<'SQL'
SELECT
  trim(ls.organization_id) AS organization_id,
  ls.email_normalized AS email_normalized,
  (
    SELECT sr.full_name
    FROM signup_requests sr
    WHERE trim(sr.organization_id) = trim(ls.organization_id)
      AND lower(trim(sr.email)) = ls.email_normalized
    ORDER BY CASE sr.status WHEN 'approved' THEN 0 WHEN 'pending' THEN 1 ELSE 2 END,
             sr.requested_at DESC
    LIMIT 1
  ) AS signup_full_name,
  'device_only' AS signup_status,
  (
    SELECT sr.issued_activation_key
    FROM signup_requests sr
    WHERE trim(sr.organization_id) = trim(ls.organization_id)
      AND lower(trim(sr.email)) = ls.email_normalized
      AND sr.status = 'approved'
    ORDER BY sr.reviewed_at DESC
    LIMIT 1
  ) AS issued_activation_key,
  ls.last_activation_code AS last_activation_code,
  ls.trial_end_at AS trial_end_at,
  ls.subscription_annual_until AS subscription_annual_until,
  ls.admin_valid_until AS admin_valid_until,
  COALESCE(ls.access_suspended, 0) AS access_suspended,
  COALESCE(ls.legacy_activated, 0) AS legacy_activated,
  ls.updated_at AS updated_at
FROM license_snapshots ls
WHERE NOT EXISTS (
  SELECT 1
  FROM signup_requests sr2
  WHERE trim(sr2.organization_id) = trim(ls.organization_id)
    AND lower(trim(sr2.email)) = ls.email_normalized
)
SQL;
        try {
            $rowsA = $pdo->query($sqlSignups)->fetchAll(PDO::FETCH_ASSOC);
            $rowsB = $pdo->query($sqlDeviceOnly)->fetchAll(PDO::FETCH_ASSOC);
        } catch (Throwable $e) {
            error_log('[activation] licenses/snapshots: ' . $e->getMessage());
            activation_json(500, ['error' => 'server', 'detail' => 'licenses_query']);
        }
        $merged = array_merge($rowsA, $rowsB);
        if ($q !== '') {
            $merged = array_values(
                array_filter(
                    $merged,
                    static function (array $row) use ($q): bool {
                        $blob = ($row['organization_id'] ?? '')
                            . ' ' . ($row['email_normalized'] ?? '')
                            . ' ' . ($row['signup_full_name'] ?? '')
                            . ' ' . ($row['signup_status'] ?? '')
                            . ' ' . ($row['issued_activation_key'] ?? '')
                            . ' ' . ($row['last_activation_code'] ?? '');

                        return stripos($blob, $q) !== false;
                    },
                ),
            );
        }
        if ($statusFilter !== 'all') {
            $merged = array_values(array_filter(
                $merged,
                static function (array $row) use ($statusFilter): bool {
                    return strtolower((string) ($row['signup_status'] ?? '')) === $statusFilter;
                },
            ));
        }
        if ($suspFilter !== 'all') {
            $wantSusp = $suspFilter === 'yes';
            $merged = array_values(array_filter(
                $merged,
                static function (array $row) use ($wantSusp): bool {
                    $susp = (int) ($row['access_suspended'] ?? 0) !== 0;
                    return $wantSusp ? $susp : !$susp;
                },
            ));
        }
        usort(
            $merged,
            static function (array $a, array $b): int {
                $ta = strtotime((string) ($a['updated_at'] ?? '')) ?: 0;
                $tb = strtotime((string) ($b['updated_at'] ?? '')) ?: 0;

                return $tb <=> $ta;
            },
        );
        $itemsAll = [];
        foreach ($merged as $row) {
            $susp = (int) ($row['access_suspended'] ?? 0) !== 0;
            $eff = $susp ? null : activation_latest_iso_date(
                isset($row['admin_valid_until']) ? (string) $row['admin_valid_until'] : null,
                isset($row['subscription_annual_until']) ? (string) $row['subscription_annual_until'] : null,
            );
            $daysRem = activation_days_remaining($eff);
            if ($expiringDays === -2) {
                if ($daysRem === null || $daysRem >= 0) {
                    continue;
                }
            } elseif ($expiringDays >= 0) {
                if ($daysRem === null || $daysRem > $expiringDays || $daysRem < 0) {
                    continue;
                }
            }
            $rawKey = isset($row['issued_activation_key']) ? trim((string) $row['issued_activation_key']) : '';
            $lastKey = isset($row['last_activation_code']) ? trim((string) $row['last_activation_code']) : '';
            $shownKey = $rawKey !== '' ? $rawKey : ($lastKey !== '' ? $lastKey : '');
            $itemsAll[] = [
                'organizationId' => $row['organization_id'],
                'email' => $row['email_normalized'],
                'signupStatus' => isset($row['signup_status']) ? (string) $row['signup_status'] : null,
                'trialEndAt' => $row['trial_end_at'] ?? null,
                'subscriptionDeviceUntil' => $row['subscription_annual_until'] ?? null,
                'adminValidUntil' => $row['admin_valid_until'] ?? null,
                'accessSuspended' => $susp,
                'effectiveAnnualUntil' => $eff,
                'effectiveDaysRemaining' => $daysRem,
                'legacyActivated' => (int) ($row['legacy_activated'] ?? 0) !== 0,
                'updatedAt' => $row['updated_at'] ?? null,
                'holderName' => $row['signup_full_name'] ?? null,
                'activationCode' => $shownKey !== '' ? $shownKey : null,
            ];
        }
        $total = count($itemsAll);
        $items = array_slice($itemsAll, $offset, $limit);
        $cntS = (int) ($pdo->query('SELECT COUNT(*) AS c FROM signup_requests')->fetch(PDO::FETCH_ASSOC)['c'] ?? 0);
        $cntL = (int) ($pdo->query('SELECT COUNT(*) AS c FROM license_snapshots')->fetch(PDO::FETCH_ASSOC)['c'] ?? 0);
        activation_json(200, [
            'items' => $items,
            'total' => $total,
            'limit' => $limit,
            'offset' => $offset,
            'dbCounts' => [
                'signupRequests' => $cntS,
                'licenseSnapshots' => $cntL,
            ],
        ]);
    }

    if ($method === 'POST' && $path === '/admin/licenses/apply') {
        $admin = activation_require_admin($config, $pdo);
        $body = activation_json_body();
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        $action = trim((string) ($body['action'] ?? ''));
        if ($organizationId === '' || strpos($email, '@') === false) {
            activation_json(400, ['error' => 'validation']);
        }
        $allowedApply = [
            'freeze',
            'unfreeze',
            'delete_snapshot',
            'extend_subscription',
            'renew_subscription',
            'set_subscription_until',
        ];
        if (!in_array($action, $allowedApply, true)) {
            activation_json(400, ['error' => 'unknown_action']);
        }
        if (in_array($action, ['freeze', 'unfreeze'], true)) {
            activation_require_perm($admin, $action);
        } elseif (in_array($action, ['extend_subscription', 'renew_subscription', 'set_subscription_until'], true)) {
            activation_require_perm($admin, 'extend');
        } else {
            activation_require_perm($admin, 'delete');
        }
        $res = activation_apply_license_action($pdo, $admin, $organizationId, $email, $action, $body);
        if (empty($res['ok'])) {
            $err = (string) ($res['error'] ?? 'server');
            if ($err === 'validation') {
                activation_json(400, ['error' => 'validation']);
            }
            if ($err === 'unknown_action') {
                activation_json(400, ['error' => 'unknown_action']);
            }
            activation_json(500, ['error' => 'server']);
        }
        activation_json(200, $res);
    }

    if ($method === 'POST' && $path === '/admin/licenses/distributor-cloud') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'extend');
        $body = activation_json_body();
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        $action = trim((string) ($body['action'] ?? ''));
        if ($organizationId === '' || strpos($email, '@') === false || $action === '') {
            activation_json(400, ['error' => 'validation']);
        }
        $allowed = [
            'extend_distributor_cloud',
            'set_distributor_cloud_until',
            'set_distributor_seats',
            'clear_distributor_cloud',
        ];
        if (!in_array($action, $allowed, true)) {
            activation_json(400, ['error' => 'unknown_action']);
        }
        $res = distributor_license_apply_admin_action(
            $pdo,
            $admin,
            $organizationId,
            $email,
            $action,
            $body,
        );
        if (empty($res['ok'])) {
            $err = (string) ($res['error'] ?? 'server');
            activation_json($err === 'validation' ? 400 : ($err === 'unknown_action' ? 400 : 500), [
                'error' => $err,
            ]);
        }
        activation_json(200, array_merge(['ok' => true], $res));
    }

    if ($method === 'POST' && $path === '/admin/vouchers/distributor-cloud') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'extend');
        $body = activation_json_body();
        $code = activation_voucher_normalize((string) ($body['code'] ?? ''));
        $action = trim((string) ($body['action'] ?? ''));
        if ($code === '' || $action === '') {
            activation_json(400, ['error' => 'validation']);
        }
        $allowed = [
            'extend_distributor_cloud',
            'set_distributor_cloud_until',
            'set_distributor_seats',
            'clear_distributor_cloud',
            'enable_distributor_cloud',
        ];
        if (!in_array($action, $allowed, true)) {
            activation_json(400, ['error' => 'unknown_action']);
        }
        $res = distributor_license_apply_voucher_admin_action(
            $pdo,
            $admin,
            $code,
            $action,
            $body,
        );
        if (empty($res['ok'])) {
            $err = (string) ($res['error'] ?? 'server');
            $status = match ($err) {
                'validation', 'unknown_action' => 400,
                'voucher_not_found' => 404,
                default => 500,
            };
            activation_json($status, ['error' => $err]);
        }
        activation_json(200, array_merge(['ok' => true], $res));
    }

    if ($method === 'POST' && $path === '/admin/licenses/bulk_apply') {
        $admin = activation_require_admin($config, $pdo);
        $body = activation_json_body();
        $action = trim((string) ($body['action'] ?? ''));
        $allowedBulk = ['freeze', 'unfreeze', 'delete_snapshot'];
        if (!in_array($action, $allowedBulk, true)) {
            activation_json(400, ['error' => 'unknown_action']);
        }
        if (in_array($action, ['freeze', 'unfreeze'], true)) {
            activation_require_perm($admin, $action);
        } else {
            activation_require_perm($admin, 'delete');
        }
        $items = $body['items'] ?? null;
        if ($action === '' || !is_array($items) || count($items) < 1) {
            activation_json(400, ['error' => 'validation']);
        }
        if (count($items) > 500) {
            activation_json(400, ['error' => 'validation']);
        }
        $results = [];
        $okCount = 0;
        $failCount = 0;
        foreach ($items as $it) {
            $org = is_array($it) ? (string) ($it['organizationId'] ?? '') : '';
            $em = is_array($it) ? (string) ($it['email'] ?? '') : '';
            $r = activation_apply_license_action($pdo, $admin, $org, $em, $action, $body);
            $row = [
                'organizationId' => trim($org),
                'email' => strtolower(trim($em)),
                'ok' => !empty($r['ok']),
                'error' => $r['error'] ?? null,
                'adminValidUntil' => $r['adminValidUntil'] ?? null,
            ];
            $results[] = $row;
            if (!empty($r['ok'])) {
                $okCount++;
            } else {
                $failCount++;
            }
        }
        activation_log_subscriber_event($pdo, 'bulk', 'bulk', $admin, 'bulk_license_action', [
            'action' => $action,
            'ok' => $okCount,
            'failed' => $failCount,
            'count' => count($results),
        ]);
        activation_json(200, ['ok' => true, 'action' => $action, 'okCount' => $okCount, 'failCount' => $failCount, 'results' => $results]);
    }

    if ($method === 'POST' && $path === '/admin/licenses/delete') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'delete');
        $body = activation_json_body();
        $organizationId = trim((string) ($body['organizationId'] ?? ''));
        $email = strtolower(trim((string) ($body['email'] ?? '')));
        if ($organizationId === '' || strpos($email, '@') === false) {
            activation_json(400, ['error' => 'validation']);
        }
        try {
            $pdo->beginTransaction();
            $st = $pdo->prepare(
                'DELETE FROM license_snapshots WHERE organization_id = ? AND email_normalized = ?',
            );
            $st->execute([$organizationId, $email]);
            $nSnap = $st->rowCount();
            $st2 = $pdo->prepare(
                'DELETE FROM signup_requests WHERE organization_id = ? AND lower(trim(email)) = ?',
            );
            $st2->execute([$organizationId, $email]);
            $nSign = $st2->rowCount();
            activation_log_subscriber_event($pdo, $organizationId, $email, $admin, 'subscriber_deleted', [
                'deletedSnapshots' => $nSnap,
                'deletedSignups' => $nSign,
            ]);
            $pdo->commit();
            activation_json(200, [
                'ok' => true,
                'deletedSnapshots' => $nSnap,
                'deletedSignups' => $nSign,
            ]);
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            error_log('[activation] licenses/delete: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }
    }

    if ($method === 'POST' && $path === '/admin/broadcast-notices/publish') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'notifications');
        $body = activation_json_body();
        $message = trim((string) ($body['message'] ?? ''));
        $title = trim((string) ($body['title'] ?? ''));
        $msgLen = function_exists('mb_strlen') ? mb_strlen($message) : strlen($message);
        if ($msgLen < 2) {
            activation_json(400, ['error' => 'validation', 'message' => 'الرسالة قصيرة جداً.']);
        }
        if ($msgLen > 2000) {
            activation_json(400, ['error' => 'validation', 'message' => 'الرسالة طويلة جداً.']);
        }
        $now = activation_now_iso();
        $id = activation_uuid();
        $createdBy = activation_admin_reviewer_label($admin);
        try {
            $pdo->beginTransaction();
            $rev = $pdo->prepare(
                'UPDATE broadcast_notices SET revoked_at = ? WHERE revoked_at IS NULL',
            );
            $rev->execute([$now]);
            $ins = $pdo->prepare(
                'INSERT INTO broadcast_notices (id, title, message, created_at, created_by_admin, revoked_at)
                 VALUES (?, ?, ?, ?, ?, NULL)',
            );
            $ins->execute([
                $id,
                $title !== '' ? $title : null,
                $message,
                $now,
                $createdBy,
            ]);
            $pdo->commit();
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            error_log('[activation] broadcast-notices/publish: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }
        activation_log_subscriber_event($pdo, 'broadcast', 'broadcast', $admin, 'broadcast_notice_published', [
            'noticeId' => $id,
            'title' => $title,
            'messageLength' => $msgLen,
        ]);
        activation_json(200, [
            'ok' => true,
            'noticeId' => $id,
            'createdAt' => $now,
            'title' => $title !== '' ? $title : 'تنبيه من إدارة MizaPos',
            'message' => $message,
        ]);
    }

    if ($method === 'GET' && $path === '/admin/broadcast-notices/active') {
        activation_require_admin($config, $pdo);
        $st = $pdo->query(
            'SELECT id, title, message, created_at, created_by_admin
             FROM broadcast_notices
             WHERE revoked_at IS NULL
             ORDER BY created_at DESC
             LIMIT 1',
        );
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            activation_json(200, ['ok' => true, 'notice' => null]);
        }
        activation_json(200, [
            'ok' => true,
            'notice' => [
                'id' => (string) ($row['id'] ?? ''),
                'title' => trim((string) ($row['title'] ?? '')) !== ''
                    ? trim((string) $row['title'])
                    : 'تنبيه من إدارة MizaPos',
                'message' => (string) ($row['message'] ?? ''),
                'createdAt' => (string) ($row['created_at'] ?? ''),
                'createdBy' => (string) ($row['created_by_admin'] ?? ''),
            ],
        ]);
    }

    if ($method === 'POST' && $path === '/admin/notifications/run') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'notifications');
        $out = activation_run_expiry_notifications($pdo, $config, $admin);
        activation_json(200, ['ok' => true] + $out);
    }

    if ($method === 'POST' && $path === '/admin/notifications/preview') {
        activation_require_admin($config, $pdo);
        $body = activation_json_body();
        $org = (string) ($body['organizationId'] ?? '');
        $email = (string) ($body['email'] ?? '');
        $days = (int) ($body['days'] ?? 3);
        $out = activation_build_notification_preview($pdo, $config, $org, $email, $days);
        if (!empty($out['error']) && $out['error'] === 'validation') {
            activation_json(400, ['error' => 'validation']);
        }
        activation_json(200, $out);
    }

    if ($method === 'POST' && $path === '/admin/notifications/test') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'notifications');
        require_once __DIR__ . '/mailer.php';
        $body = activation_json_body();
        $org = (string) ($body['organizationId'] ?? '');
        $email = (string) ($body['email'] ?? '');
        $days = (int) ($body['days'] ?? 3);
        $toOverride = trim((string) ($body['toEmail'] ?? ''));
        if ($toOverride === '' || strpos($toOverride, '@') === false) {
            activation_json(400, ['error' => 'validation']);
        }
        $prev = activation_build_notification_preview($pdo, $config, $org, $email, $days);
        if (empty($prev['ok'])) {
            activation_json(400, ['error' => 'validation']);
        }
        $subject = (string) ($prev['subject'] ?? 'Test');
        $html = (string) ($prev['html'] ?? '');
        $subject = '[TEST] ' . $subject;
        $res = activation_send_email($config, $toOverride, $subject, $html);
        $wa = activation_send_whatsapp($config, trim($org), strtolower(trim($email)), $days, null);
        activation_log_subscriber_event($pdo, trim($org), strtolower(trim($email)), $admin, 'expiry_notification_test_sent', [
            'toEmail' => $toOverride,
            'days' => $days,
            'dryRun' => !empty($res['dryRun']),
            'mail' => $res,
            'whatsapp' => $wa,
        ]);
        activation_json(200, ['ok' => !empty($res['ok']), 'mail' => $res, 'whatsapp' => $wa]);
    }

    /* -------------------- Admin: vouchers management -------------------- */

    if ($method === 'POST' && $path === '/admin/vouchers/generate') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'extend');
        $body = activation_json_body();
        $count = max(1, min(500, (int) ($body['count'] ?? 1)));
        $note = trim((string) ($body['note'] ?? ''));
        $useTyped = !empty($body['useTypedDeviceLimits']);
        $maxDevices = max(1, min(99, (int) ($body['maxDevices'] ?? 1)));
        $maxDesktop = max(0, min(50, (int) ($body['maxDesktopDevices'] ?? 0)));
        $maxAndroid = max(0, min(50, (int) ($body['maxAndroidDevices'] ?? 0)));
        if ($useTyped) {
            if ($maxDesktop + $maxAndroid < 1) {
                activation_json(400, ['error' => 'validation']);
            }
            $maxDevices = $maxDesktop + $maxAndroid;
        }
        $includeDistCloud = !empty($body['includeDistributorCloud']);
        $distCloudDays = $includeDistCloud
            ? max(1, min(3660, (int) ($body['distributorCloudDays'] ?? 365)))
            : null;
        $distSeatsRaw = $body['maxDistributorSeats'] ?? null;
        $distSeats = null;
        if ($includeDistCloud && $distSeatsRaw !== null && $distSeatsRaw !== '') {
            $distSeats = max(0, min(9999, (int) $distSeatsRaw));
        }
        $batchId = activation_uuid();
        $now = activation_now_iso();
        $createdBy = activation_admin_reviewer_label($admin);
        $codes = [];
        try {
            $pdo->beginTransaction();
            $check = $pdo->prepare('SELECT 1 FROM vouchers WHERE code = ?');
            $ins = $pdo->prepare(
                'INSERT INTO vouchers (
                   code, max_devices, max_desktop_devices, max_android_devices,
                   status, batch_id, note, created_at, created_by_admin,
                   distributor_cloud_days, max_distributor_seats
                 ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            );
            $generated = 0;
            $safety = 0;
            while ($generated < $count && $safety < $count * 8) {
                $safety++;
                $code = activation_voucher_generate_code();
                $check->execute([$code]);
                if ($check->fetch(PDO::FETCH_ASSOC)) {
                    continue;
                }
                $ins->execute([
                    $code,
                    $maxDevices,
                    $useTyped ? $maxDesktop : null,
                    $useTyped ? $maxAndroid : null,
                    'unused',
                    $batchId,
                    $note !== '' ? $note : null,
                    $now,
                    $createdBy,
                    $distCloudDays,
                    $distSeats,
                ]);
                $codes[] = $code;
                $generated++;
            }
            $pdo->commit();
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            error_log('[activation] vouchers/generate: ' . $e->getMessage());
            activation_json(500, ['error' => 'server']);
        }
        activation_json(200, [
            'ok' => true,
            'batchId' => $batchId,
            'count' => count($codes),
            'maxDevices' => $maxDevices,
            'useTypedDeviceLimits' => $useTyped,
            'maxDesktopDevices' => $useTyped ? $maxDesktop : null,
            'maxAndroidDevices' => $useTyped ? $maxAndroid : null,
            'note' => $note,
            'includeDistributorCloud' => $includeDistCloud,
            'distributorCloudDays' => $distCloudDays,
            'maxDistributorSeats' => $distSeats,
            'codes' => $codes,
            'createdAt' => $now,
        ]);
    }

    if ($method === 'GET' && $path === '/admin/vouchers/list') {
        activation_require_admin($config, $pdo);
        $status = strtolower(trim((string) ($_GET['status'] ?? '')));
        $batchId = trim((string) ($_GET['batchId'] ?? ''));
        $search = strtoupper(trim((string) ($_GET['search'] ?? '')));
        $limit = max(1, min(500, (int) ($_GET['limit'] ?? 200)));
        $offset = max(0, (int) ($_GET['offset'] ?? 0));
        $where = '1=1';
        $bind = [];
        if (in_array($status, ['unused', 'redeemed', 'revoked'], true)) {
            $where .= ' AND status = ?';
            $bind[] = $status;
        }
        if ($batchId !== '') {
            $where .= ' AND batch_id = ?';
            $bind[] = $batchId;
        }
        if ($search !== '') {
            $where .= ' AND (UPPER(code) LIKE ? OR UPPER(note) LIKE ? OR UPPER(redeemed_by_email) LIKE ?)';
            $like = '%' . $search . '%';
            $bind[] = $like;
            $bind[] = $like;
            $bind[] = $like;
        }
        $countSt = $pdo->prepare('SELECT COUNT(*) AS n FROM vouchers WHERE ' . $where);
        $countSt->execute($bind);
        $total = (int) ($countSt->fetch(PDO::FETCH_ASSOC)['n'] ?? 0);

        $sql = 'SELECT * FROM vouchers WHERE ' . $where
            . ' ORDER BY created_at DESC LIMIT ' . $limit . ' OFFSET ' . $offset;
        $st = $pdo->prepare($sql);
        $st->execute($bind);
        $items = [];
        foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $v) {
            $items[] = activation_voucher_row_with_stats($pdo, $v);
        }
        $statsSt = $pdo->query(
            "SELECT
               SUM(CASE WHEN status = 'unused' THEN 1 ELSE 0 END) AS unused,
               SUM(CASE WHEN status = 'redeemed' THEN 1 ELSE 0 END) AS redeemed,
               SUM(CASE WHEN status = 'revoked' THEN 1 ELSE 0 END) AS revoked,
               COUNT(*) AS total
             FROM vouchers",
        );
        $stats = $statsSt->fetch(PDO::FETCH_ASSOC) ?: [];
        activation_json(200, [
            'ok' => true,
            'items' => $items,
            'total' => $total,
            'limit' => $limit,
            'offset' => $offset,
            'stats' => [
                'unused' => (int) ($stats['unused'] ?? 0),
                'redeemed' => (int) ($stats['redeemed'] ?? 0),
                'revoked' => (int) ($stats['revoked'] ?? 0),
                'total' => (int) ($stats['total'] ?? 0),
            ],
        ]);
    }

    if ($method === 'GET' && $path === '/admin/vouchers/detail') {
        activation_require_admin($config, $pdo);
        $code = activation_voucher_normalize((string) ($_GET['code'] ?? ''));
        if ($code === '') {
            activation_json(400, ['error' => 'validation']);
        }
        $st = $pdo->prepare('SELECT * FROM vouchers WHERE code = ?');
        $st->execute([$code]);
        $v = $st->fetch(PDO::FETCH_ASSOC);
        if (!$v) {
            activation_json(404, ['error' => 'not_found']);
        }
        $dedupedRows = activation_voucher_dedupe_redemptions($pdo, $code);
        $dev = $pdo->prepare(
            'SELECT installation_id, organization_id, subscriber_email,
                    device_fingerprint, computer_name, os_name, os_user, device_platform,
                    redeemed_at, last_seen_at, revoked_at
             FROM voucher_redemptions WHERE voucher_code = ?
             ORDER BY redeemed_at DESC',
        );
        $dev->execute([$code]);
        $devices = $dev->fetchAll(PDO::FETCH_ASSOC);
        $totalRows = count($devices);
        $activeDevices = activation_voucher_active_device_count($pdo, $code);

        // إثراء البيانات بمعلومات المشترك (الاسم، الهاتف، رمز الدولة)
        // المُسجَّلة في signup_requests وقت إنشاء الحساب.
        $subscriber = null;
        $email = trim((string) ($v['redeemed_by_email'] ?? ''));
        if ($email !== '') {
            $orgId = trim((string) ($v['redeemed_by_organization_id'] ?? ''));
            if ($orgId !== '') {
                $sub = $pdo->prepare(
                    'SELECT full_name, phone, dial_code, requested_at
                     FROM signup_requests
                     WHERE lower(trim(email)) = ? AND trim(organization_id) = trim(?)
                     ORDER BY requested_at DESC LIMIT 1',
                );
                $sub->execute([strtolower($email), $orgId]);
            } else {
                $sub = $pdo->prepare(
                    'SELECT full_name, phone, dial_code, requested_at
                     FROM signup_requests
                     WHERE lower(trim(email)) = ?
                     ORDER BY requested_at DESC LIMIT 1',
                );
                $sub->execute([strtolower($email)]);
            }
            $row = $sub->fetch(PDO::FETCH_ASSOC);
            if ($row) {
                $subscriber = [
                    'email' => $email,
                    'fullName' => (string) ($row['full_name'] ?? ''),
                    'phone' => (string) ($row['phone'] ?? ''),
                    'dialCode' => activation_normalize_dial_code((string) ($row['dial_code'] ?? '')),
                    'requestedAt' => (string) ($row['requested_at'] ?? ''),
                ];
            } else {
                $subscriber = [
                    'email' => $email,
                    'fullName' => '',
                    'phone' => '',
                    'dialCode' => '',
                    'requestedAt' => '',
                ];
            }
        }
        activation_json(200, [
            'ok' => true,
            'voucher' => activation_voucher_row_with_stats($pdo, $v),
            'devices' => $devices,
            'subscriber' => $subscriber,
            'deviceStats' => [
                'activeDevices' => $activeDevices,
                'totalRows' => $totalRows,
                'dedupedRows' => $dedupedRows,
            ],
        ]);
    }

    if ($method === 'POST' && $path === '/admin/vouchers/revoke') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'delete');
        $body = activation_json_body();
        $code = activation_voucher_normalize((string) ($body['code'] ?? ''));
        $reason = trim((string) ($body['reason'] ?? ''));
        if ($code === '') {
            activation_json(400, ['error' => 'validation']);
        }
        $now = activation_now_iso();
        $by = activation_admin_reviewer_label($admin);
        $up = $pdo->prepare(
            "UPDATE vouchers SET status = 'revoked', revoked_at = ?, revoked_by_admin = ?, revoke_reason = ?
             WHERE code = ?",
        );
        $up->execute([$now, $by, $reason !== '' ? $reason : null, $code]);
        if ($up->rowCount() === 0) {
            activation_json(404, ['error' => 'not_found']);
        }
        activation_json(200, ['ok' => true]);
    }

    if ($method === 'POST' && $path === '/admin/vouchers/restore') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'extend');
        $body = activation_json_body();
        $code = activation_voucher_normalize((string) ($body['code'] ?? ''));
        if ($code === '') {
            activation_json(400, ['error' => 'validation']);
        }
        $st = $pdo->prepare('SELECT redeemed_by_email FROM vouchers WHERE code = ?');
        $st->execute([$code]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            activation_json(404, ['error' => 'not_found']);
        }
        $newStatus = ($row['redeemed_by_email'] ?? '') !== '' ? 'redeemed' : 'unused';
        $up = $pdo->prepare(
            'UPDATE vouchers SET status = ?, revoked_at = NULL, revoked_by_admin = NULL, revoke_reason = NULL
             WHERE code = ?',
        );
        $up->execute([$newStatus, $code]);
        activation_json(200, ['ok' => true, 'status' => $newStatus]);
    }

    if ($method === 'POST' && $path === '/admin/vouchers/revoke-device') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'delete');
        $body = activation_json_body();
        $code = activation_voucher_normalize((string) ($body['code'] ?? ''));
        $installationId = trim((string) ($body['installationId'] ?? ''));
        if ($code === '' || $installationId === '') {
            activation_json(400, ['error' => 'validation']);
        }
        $now = activation_now_iso();
        $up = $pdo->prepare(
            'UPDATE voucher_redemptions SET revoked_at = ?
             WHERE voucher_code = ? AND installation_id = ? AND revoked_at IS NULL',
        );
        $up->execute([$now, $code, $installationId]);
        if ($up->rowCount() === 0) {
            activation_json(404, ['error' => 'not_found']);
        }
        activation_json(200, ['ok' => true]);
    }

    if ($method === 'POST' && $path === '/admin/vouchers/update-note') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'extend');
        $body = activation_json_body();
        $code = activation_voucher_normalize((string) ($body['code'] ?? ''));
        $note = trim((string) ($body['note'] ?? ''));
        if ($code === '') {
            activation_json(400, ['error' => 'validation']);
        }
        $up = $pdo->prepare('UPDATE vouchers SET note = ? WHERE code = ?');
        $up->execute([$note !== '' ? $note : null, $code]);
        if ($up->rowCount() === 0) {
            activation_json(404, ['error' => 'not_found']);
        }
        activation_json(200, ['ok' => true]);
    }

    /* ---- تعديل عدد أجهزة القسيمة (تطبق فقط إذا لم تتجاوز الأجهزة المُفعَّلة العدد الجديد) ---- */
    if ($method === 'POST' && $path === '/admin/vouchers/update-max-devices') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'extend');
        $body = activation_json_body();
        $code = activation_voucher_normalize((string) ($body['code'] ?? ''));
        $useTyped = !empty($body['useTypedDeviceLimits']);
        $maxDevices = max(1, min(99, (int) ($body['maxDevices'] ?? 0)));
        $maxDesktop = max(0, min(50, (int) ($body['maxDesktopDevices'] ?? 0)));
        $maxAndroid = max(0, min(50, (int) ($body['maxAndroidDevices'] ?? 0)));
        if ($code === '') {
            activation_json(400, ['error' => 'validation']);
        }
        $st = $pdo->prepare(
            'SELECT max_devices, max_desktop_devices, max_android_devices FROM vouchers WHERE code = ?',
        );
        $st->execute([$code]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            activation_json(404, ['error' => 'not_found']);
        }
        if ($useTyped) {
            if ($maxDesktop + $maxAndroid < 1) {
                activation_json(400, ['error' => 'validation']);
            }
            $maxDevices = $maxDesktop + $maxAndroid;
            $usedDesktop = activation_voucher_active_count_by_platform($pdo, $code, 'desktop');
            $usedAndroid = activation_voucher_active_count_by_platform($pdo, $code, 'android');
            if ($maxDesktop < $usedDesktop || $maxAndroid < $usedAndroid) {
                activation_json(409, [
                    'error' => 'used_exceeds_limit',
                    'usedDesktopDevices' => $usedDesktop,
                    'usedAndroidDevices' => $usedAndroid,
                    'maxDesktopDevices' => $maxDesktop,
                    'maxAndroidDevices' => $maxAndroid,
                ]);
            }
            $up = $pdo->prepare(
                'UPDATE vouchers SET max_devices = ?, max_desktop_devices = ?, max_android_devices = ? WHERE code = ?',
            );
            $up->execute([$maxDevices, $maxDesktop, $maxAndroid, $code]);
            activation_json(200, [
                'ok' => true,
                'maxDevices' => $maxDevices,
                'useTypedDeviceLimits' => true,
                'maxDesktopDevices' => $maxDesktop,
                'maxAndroidDevices' => $maxAndroid,
            ]);
        }
        if ($maxDevices < 1) {
            activation_json(400, ['error' => 'validation']);
        }
        $used = activation_voucher_active_device_count($pdo, $code);
        if ($maxDevices < $used) {
            activation_json(409, [
                'error' => 'used_exceeds_limit',
                'usedDevices' => $used,
                'maxDevices' => $maxDevices,
            ]);
        }
        $up = $pdo->prepare(
            'UPDATE vouchers SET max_devices = ?, max_desktop_devices = NULL, max_android_devices = NULL WHERE code = ?',
        );
        $up->execute([$maxDevices, $code]);
        activation_json(200, [
            'ok' => true,
            'maxDevices' => $maxDevices,
            'useTypedDeviceLimits' => false,
        ]);
    }

    /* ---- حذف نهائي للقسيمة (يحذف الأجهزة المرتبطة عبر CASCADE) ---- */
    if ($method === 'POST' && $path === '/admin/vouchers/delete') {
        $admin = activation_require_admin($config, $pdo);
        activation_require_perm($admin, 'delete');
        $body = activation_json_body();
        $code = activation_voucher_normalize((string) ($body['code'] ?? ''));
        if ($code === '') {
            activation_json(400, ['error' => 'validation']);
        }
        $pdo->beginTransaction();
        try {
            // مسح الأجهزة بشكل صريح ثم القسيمة نفسها — أكثر أماناً من الاعتماد
            // فقط على ON DELETE CASCADE (يدعم البيئات بدون PRAGMA foreign_keys).
            $pdo->prepare('DELETE FROM voucher_redemptions WHERE voucher_code = ?')
                ->execute([$code]);
            $up = $pdo->prepare('DELETE FROM vouchers WHERE code = ?');
            $up->execute([$code]);
            if ($up->rowCount() === 0) {
                $pdo->rollBack();
                activation_json(404, ['error' => 'not_found']);
            }
            $pdo->commit();
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            activation_json(500, ['error' => 'server_error']);
        }
        activation_json(200, ['ok' => true]);
    }

    if ($method === 'GET' && $path === '/admin/vouchers/export') {
        activation_require_admin($config, $pdo);
        $batchId = trim((string) ($_GET['batchId'] ?? ''));
        $status = strtolower(trim((string) ($_GET['status'] ?? '')));
        $where = '1=1';
        $bind = [];
        if ($batchId !== '') {
            $where .= ' AND batch_id = ?';
            $bind[] = $batchId;
        }
        if (in_array($status, ['unused', 'redeemed', 'revoked'], true)) {
            $where .= ' AND status = ?';
            $bind[] = $status;
        }
        $st = $pdo->prepare('SELECT * FROM vouchers WHERE ' . $where . ' ORDER BY created_at DESC');
        $st->execute($bind);
        $rows = $st->fetchAll(PDO::FETCH_ASSOC);
        $csv = "code,max_devices,status,batch_id,note,created_at,redeemed_by_email,organization_id,revoked_at\n";
        foreach ($rows as $r) {
            $line = [
                (string) $r['code'],
                (string) $r['max_devices'],
                (string) $r['status'],
                (string) ($r['batch_id'] ?? ''),
                str_replace(["\r", "\n", ','], [' ', ' ', ' '], (string) ($r['note'] ?? '')),
                (string) ($r['created_at'] ?? ''),
                (string) ($r['redeemed_by_email'] ?? ''),
                (string) ($r['redeemed_by_organization_id'] ?? ''),
                (string) ($r['revoked_at'] ?? ''),
            ];
            $csv .= implode(',', $line) . "\n";
        }
        activation_send(200, array_merge(activation_cors_headers(), [
            'Content-Type' => 'text/csv; charset=utf-8',
            'Content-Disposition' => 'attachment; filename="vouchers-' . date('Ymd-His') . '.csv"',
        ]), "\xEF\xBB\xBF" . $csv);
    }

    // لوحة إدارة القسائم: العنوان الرسمي الوحيد …/public/vouchers.html
    if ($method === 'GET') {
        $base = rtrim((string) $config['APP_BASE_PATH'], '/');
        $canonical = $base . '/public/vouchers.html';
        if ($path === '/' || $path === '' || $path === '/vouchers'
            || $path === '/public' || $path === '/public/') {
            activation_redirect($canonical);
        }
    }

    if (field_orders_dispatch($pdo, $config, $method, $path)) {
        return;
    }

    if (field_expenses_dispatch($pdo, $config, $method, $path)) {
        return;
    }

    if (field_returns_dispatch($pdo, $config, $method, $path)) {
        return;
    }

    if (field_catalog_dispatch($pdo, $config, $method, $path)) {
        return;
    }

    if (field_truck_stock_dispatch($pdo, $config, $method, $path)) {
        return;
    }

    if (team_users_dispatch($pdo, $config, $method, $path)) {
        return;
    }

    activation_json(404, ['error' => 'not_found']);
}
