<?php
declare(strict_types=1);

function activation_open_db(string $databasePath): PDO
{
    $dir = dirname($databasePath);
    if (!is_dir($dir)) {
        if (!@mkdir($dir, 0755, true) && !is_dir($dir)) {
            throw new RuntimeException('Cannot create database directory: ' . $dir);
        }
    }
    $pdo = new PDO('sqlite:' . $databasePath, null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    $pdo->exec('PRAGMA foreign_keys = ON;');
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS signup_requests (
            id TEXT PRIMARY KEY,
            organization_id TEXT NOT NULL,
            full_name TEXT NOT NULL,
            email TEXT NOT NULL,
            phone TEXT NOT NULL,
            dial_code TEXT NOT NULL,
            password_hash TEXT NOT NULL,
            requested_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            reviewed_at TEXT,
            issued_activation_key TEXT,
            reviewed_by TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_remote_signup_org_email
            ON signup_requests(organization_id, email);
        CREATE INDEX IF NOT EXISTS idx_remote_signup_org_status
            ON signup_requests(organization_id, status);
        CREATE TABLE IF NOT EXISTS admins (
            id TEXT PRIMARY KEY,
            email TEXT NOT NULL COLLATE NOCASE,
            password_hash TEXT NOT NULL,
            created_at TEXT NOT NULL,
            acl TEXT NOT NULL DEFAULT 'approver',
            admin_role TEXT NOT NULL DEFAULT 'admin',
            disabled_at TEXT,
            UNIQUE(email)
        );
        CREATE TABLE IF NOT EXISTS license_snapshots (
            organization_id TEXT NOT NULL,
            email_normalized TEXT NOT NULL,
            trial_end_at TEXT,
            subscription_annual_until TEXT,
            legacy_activated INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL,
            admin_valid_until TEXT,
            last_activation_code TEXT,
            access_suspended INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (organization_id, email_normalized)
        );
        CREATE TABLE IF NOT EXISTS subscriber_activity_log (
            id TEXT PRIMARY KEY,
            organization_id TEXT NOT NULL,
            email_normalized TEXT NOT NULL,
            actor_email TEXT,
            event_type TEXT NOT NULL,
            details_json TEXT,
            created_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_subscriber_activity_org_email_created
            ON subscriber_activity_log(organization_id, email_normalized, created_at DESC);
        CREATE TABLE IF NOT EXISTS notification_log (
            id TEXT PRIMARY KEY,
            organization_id TEXT NOT NULL,
            email_normalized TEXT NOT NULL,
            kind TEXT NOT NULL,
            status TEXT NOT NULL,
            details_json TEXT,
            created_at TEXT NOT NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS uq_notification_once
            ON notification_log(organization_id, email_normalized, kind);
        CREATE TABLE IF NOT EXISTS subscriber_devices (
            id TEXT PRIMARY KEY,
            organization_id TEXT NOT NULL,
            email_normalized TEXT NOT NULL,
            installation_id TEXT NOT NULL,
            device_fingerprint TEXT NOT NULL,
            computer_name TEXT,
            os_user TEXT,
            os_name TEXT,
            last_seen_at TEXT NOT NULL,
            revoked_at TEXT,
            UNIQUE(organization_id, email_normalized, installation_id)
        );
        CREATE INDEX IF NOT EXISTS idx_subscriber_devices_org_email
            ON subscriber_devices(organization_id, email_normalized, last_seen_at DESC);
        CREATE TABLE IF NOT EXISTS activation_redeems (
            signup_request_id TEXT NOT NULL,
            installation_id TEXT NOT NULL,
            redeemed_at TEXT NOT NULL,
            PRIMARY KEY (signup_request_id, installation_id)
        );
        CREATE INDEX IF NOT EXISTS idx_activation_redeems_installation
            ON activation_redeems(installation_id);
        CREATE TABLE IF NOT EXISTS device_link_claims (
            installation_id TEXT PRIMARY KEY,
            organization_id TEXT NOT NULL,
            email_normalized TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_device_link_claims_org_email
            ON device_link_claims(organization_id, email_normalized, updated_at DESC);
        CREATE TABLE IF NOT EXISTS vouchers (
            code TEXT PRIMARY KEY,
            max_devices INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'unused',
            batch_id TEXT,
            note TEXT,
            created_at TEXT NOT NULL,
            created_by_admin TEXT,
            first_redeemed_at TEXT,
            redeemed_by_email TEXT,
            redeemed_by_organization_id TEXT,
            revoked_at TEXT,
            revoked_by_admin TEXT,
            revoke_reason TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_vouchers_status ON vouchers(status);
        CREATE INDEX IF NOT EXISTS idx_vouchers_batch ON vouchers(batch_id);
        CREATE INDEX IF NOT EXISTS idx_vouchers_subscriber
            ON vouchers(redeemed_by_email, redeemed_by_organization_id);
        CREATE TABLE IF NOT EXISTS voucher_redemptions (
            voucher_code TEXT NOT NULL,
            installation_id TEXT NOT NULL,
            organization_id TEXT NOT NULL,
            subscriber_email TEXT NOT NULL,
            device_fingerprint TEXT,
            computer_name TEXT,
            os_name TEXT,
            os_user TEXT,
            redeemed_at TEXT NOT NULL,
            last_seen_at TEXT NOT NULL,
            revoked_at TEXT,
            PRIMARY KEY (voucher_code, installation_id),
            FOREIGN KEY (voucher_code) REFERENCES vouchers(code) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_voucher_redemptions_install
            ON voucher_redemptions(installation_id);
        CREATE INDEX IF NOT EXISTS idx_voucher_redemptions_email
            ON voucher_redemptions(subscriber_email, organization_id);
        CREATE TABLE IF NOT EXISTS website_contact_messages (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            email TEXT NOT NULL,
            phone TEXT,
            topic TEXT NOT NULL,
            message TEXT NOT NULL,
            ip TEXT,
            user_agent TEXT,
            mail_sent INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_website_contact_created
            ON website_contact_messages(created_at DESC);
        CREATE TABLE IF NOT EXISTS broadcast_notices (
            id TEXT PRIMARY KEY,
            title TEXT,
            message TEXT NOT NULL,
            created_at TEXT NOT NULL,
            created_by_admin TEXT,
            revoked_at TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_broadcast_notices_active
            ON broadcast_notices(created_at DESC);
        CREATE TABLE IF NOT EXISTS broadcast_notice_dismissals (
            notice_id TEXT NOT NULL,
            installation_id TEXT NOT NULL,
            dismissed_at TEXT NOT NULL,
            PRIMARY KEY (notice_id, installation_id),
            FOREIGN KEY (notice_id) REFERENCES broadcast_notices(id) ON DELETE CASCADE
        );
    ");
    $lsCols = $pdo->query('PRAGMA table_info(license_snapshots)')->fetchAll(PDO::FETCH_ASSOC);
    $lsNames = [];
    foreach ($lsCols as $c) {
        $lsNames[$c['name']] = true;
    }
    if (!isset($lsNames['admin_valid_until'])) {
        $pdo->exec('ALTER TABLE license_snapshots ADD COLUMN admin_valid_until TEXT');
    }
    if (!isset($lsNames['access_suspended'])) {
        $pdo->exec('ALTER TABLE license_snapshots ADD COLUMN access_suspended INTEGER NOT NULL DEFAULT 0');
    }
    if (!isset($lsNames['last_activation_code'])) {
        $pdo->exec('ALTER TABLE license_snapshots ADD COLUMN last_activation_code TEXT');
    }
    if (!isset($lsNames['distributor_cloud_until'])) {
        $pdo->exec('ALTER TABLE license_snapshots ADD COLUMN distributor_cloud_until TEXT');
    }
    if (!isset($lsNames['max_distributor_seats'])) {
        $pdo->exec('ALTER TABLE license_snapshots ADD COLUMN max_distributor_seats INTEGER');
    }
    $cols = $pdo->query('PRAGMA table_info(admins)')->fetchAll(PDO::FETCH_ASSOC);
    $names = [];
    foreach ($cols as $c) {
        $names[$c['name']] = true;
    }
    if (!isset($names['acl'])) {
        $pdo->exec("ALTER TABLE admins ADD COLUMN acl TEXT NOT NULL DEFAULT 'approver'");
    }
    if (!isset($names['admin_role'])) {
        $pdo->exec("ALTER TABLE admins ADD COLUMN admin_role TEXT NOT NULL DEFAULT 'admin'");
    }
    if (!isset($names['disabled_at'])) {
        $pdo->exec("ALTER TABLE admins ADD COLUMN disabled_at TEXT");
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
    $voucherCols = $pdo->query('PRAGMA table_info(vouchers)')->fetchAll(PDO::FETCH_ASSOC);
    $voucherNames = [];
    foreach ($voucherCols as $c) {
        $voucherNames[$c['name']] = true;
    }
    if (!isset($voucherNames['max_desktop_devices'])) {
        $pdo->exec('ALTER TABLE vouchers ADD COLUMN max_desktop_devices INTEGER');
    }
    if (!isset($voucherNames['max_android_devices'])) {
        $pdo->exec('ALTER TABLE vouchers ADD COLUMN max_android_devices INTEGER');
    }
    if (!isset($voucherNames['distributor_cloud_days'])) {
        $pdo->exec('ALTER TABLE vouchers ADD COLUMN distributor_cloud_days INTEGER');
    }
    if (!isset($voucherNames['distributor_cloud_until'])) {
        $pdo->exec('ALTER TABLE vouchers ADD COLUMN distributor_cloud_until TEXT');
    }
    if (!isset($voucherNames['max_distributor_seats'])) {
        $pdo->exec('ALTER TABLE vouchers ADD COLUMN max_distributor_seats INTEGER');
    }
    $vrCols = $pdo->query('PRAGMA table_info(voucher_redemptions)')->fetchAll(PDO::FETCH_ASSOC);
    $vrNames = [];
    foreach ($vrCols as $c) {
        $vrNames[$c['name']] = true;
    }
    if (!isset($vrNames['device_platform'])) {
        $pdo->exec('ALTER TABLE voucher_redemptions ADD COLUMN device_platform TEXT');
    }
    return $pdo;
}

function activation_uuid(): string
{
    $b = random_bytes(16);
    $b[6] = chr((ord($b[6]) & 0x0f) | 0x40);
    $b[8] = chr((ord($b[8]) & 0x3f) | 0x80);
    return vsprintf('%s%s-%s-%s-%s%s%s', str_split(bin2hex($b), 4));
}

/** @return true إذا تم الإدراج، false إذا البريد مسجّل مسبقاً */
function activation_admin_insert(PDO $pdo, string $email, string $plain, string $role = 'admin'): bool
{
    $email = strtolower(trim($email));
    $role = strtolower(trim($role));
    if (!in_array($role, ['admin', 'billing', 'support', 'viewer'], true)) {
        $role = 'admin';
    }
    if (strpos($email, '@') === false || strlen($plain) < 8) {
        throw new InvalidArgumentException('validation');
    }
    $st = $pdo->prepare('SELECT id FROM admins WHERE lower(trim(email)) = ?');
    $st->execute([$email]);
    if ($st->fetch(PDO::FETCH_ASSOC)) {
        return false;
    }
    $id = activation_uuid();
    $hash = password_hash($plain, PASSWORD_BCRYPT, ['cost' => 10]);
    $now = (new DateTimeImmutable('now', new DateTimeZone('UTC')))->format('Y-m-d\TH:i:s.v\Z');
    $ins = $pdo->prepare(
        'INSERT INTO admins (id, email, password_hash, created_at, acl, admin_role) VALUES (?, ?, ?, ?, ?, ?)',
    );
    $acl = $role === 'viewer' ? 'viewer' : 'approver';
    $ins->execute([$id, $email, $hash, $now, $acl, $role]);
    return true;
}
