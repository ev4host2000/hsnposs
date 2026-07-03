<?php
declare(strict_types=1);

/** اختبار مزامنة فريق العمل — php drhsn/scripts/smoke_team_users.php */
require __DIR__ . '/../includes/config.php';
require __DIR__ . '/../includes/db.php';
require __DIR__ . '/../includes/handlers.php';

$config = activation_config();
$pdo = activation_open_db($config['DATABASE_PATH']);
team_users_ensure_schema($pdo);

$org = 'smoke-team-org';
$email = 'teamusers-smoke@example.com';
$now = activation_now_iso();
$userId = activation_uuid();
$pwdHash = password_hash('dist1234', PASSWORD_BCRYPT);

$pdo->prepare('DELETE FROM signup_requests WHERE lower(trim(email)) = ?')->execute([$email]);
$pdo->prepare('DELETE FROM team_users WHERE trim(organization_id) = trim(?)')->execute([$org]);
$pdo->prepare('DELETE FROM team_users_meta WHERE trim(organization_id) = trim(?)')->execute([$org]);
$pdo->prepare(
    'INSERT INTO signup_requests (
        id, organization_id, full_name, email, phone, dial_code, password_hash, requested_at, status, email_verified
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)',
)->execute([
    activation_uuid(),
    $org,
    'Team Smoke Owner',
    $email,
    '599000002',
    '+970',
    password_hash('owner1234', PASSWORD_BCRYPT),
    $now,
    'approved',
]);

$pdo->prepare(
    'INSERT INTO team_users (
        id, organization_id, user_id, username, email, full_name, role, branch_id,
        password_hash, dial_code, phone, account_status, deleted, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)',
)->execute([
    activation_uuid(),
    $org,
    $userId,
    'distributor1',
    'distributor1@legacy.mizapos',
    'موزّع تجريبي',
    'distributor',
    'branch-1',
    $pwdHash,
    '+970',
    '599111111',
    'active',
    $now,
]);
team_users_bump_meta($pdo, $org, $email);

$meta = team_users_fetch_meta($pdo, $org);
if ($meta === null) {
    fwrite(STDERR, "meta missing\n");
    exit(1);
}
$users = team_users_fetch_all($pdo, $org, false);
if (count($users) !== 1 || ($users[0]['userId'] ?? '') !== $userId) {
    fwrite(STDERR, "users fetch failed\n");
    exit(1);
}

$pdo->prepare(
    'UPDATE team_users SET deleted = 1, updated_at = ?
     WHERE trim(organization_id) = trim(?) AND trim(user_id) = trim(?)',
)->execute([$now, $org, $userId]);
team_users_bump_meta($pdo, $org, $email);
$active = team_users_fetch_all($pdo, $org, false);
if (count($active) !== 0) {
    fwrite(STDERR, "soft delete failed\n");
    exit(1);
}

echo "ok team_users schema + upsert + tombstone\n";

$pdo->prepare('DELETE FROM team_users WHERE trim(organization_id) = trim(?)')->execute([$org]);
$pdo->prepare('DELETE FROM team_users_meta WHERE trim(organization_id) = trim(?)')->execute([$org]);
$pdo->prepare('DELETE FROM signup_requests WHERE lower(trim(email)) = ?')->execute([$email]);

exit(0);
