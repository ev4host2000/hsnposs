<?php
declare(strict_types=1);

require_once __DIR__ . '/mailer.php';

function activation_public_website_url(array $config): string
{
    $u = trim((string) ($config['PUBLIC_WEBSITE_URL'] ?? 'https://mizapos.com'));

    return rtrim($u, '/');
}

function activation_signup_verify_page_url(array $config, string $token): string
{
    $site = activation_public_website_url($config);
    $base = trim((string) ($config['APP_BASE_PATH'] ?? ''));
    if ($base === '' || $base === '/') {
        $base = '/drhsn';
    }
    if ($base[0] !== '/') {
        $base = '/' . $base;
    }

    return $site . $base . '/public/verify-email.html?token=' . rawurlencode($token);
}

function activation_signup_email_token(): string
{
    return bin2hex(random_bytes(32));
}

function activation_signup_verify_expires_iso(): string
{
    return (new DateTimeImmutable('now', new DateTimeZone('UTC')))
        ->modify('+72 hours')
        ->format('Y-m-d\TH:i:s.v\Z');
}

function activation_signup_welcome_body_html(
    array $config,
    string $fullName,
    string $email,
    string $verifyUrl,
): string {
    $h = static fn (string $s): string => htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    $name = trim($fullName) !== '' ? trim($fullName) : $email;
    $site = activation_public_website_url($config);
    $safeName = $h($name);
    $safeEmail = $h($email);
    $safeSite = $h($site);
    $safeVerify = $h($verifyUrl);

    return '<div dir="rtl" style="font-family:Segoe UI,Tahoma,Cairo,sans-serif;font-size:15px;line-height:1.75;color:#0f172a;max-width:560px">'
        . '<p style="margin:0 0 12px">مرحباً <strong>' . $safeName . '</strong>،</p>'
        . '<p style="margin:0 0 12px">شكراً لتسجيلك في <strong>MizaPos</strong> — برنامج المحاسبة والمبيعات.</p>'
        . '<p style="margin:0 0 12px">الموقع الرسمي للبرنامج:<br>'
        . '<a href="' . $safeSite . '" style="color:#4f46e5;font-weight:700">' . $safeSite . '</a></p>'
        . '<p style="margin:0 0 16px">لتأكيد أن هذا البريد (<strong>' . $safeEmail . '</strong>) يخصك فعلاً، اضغط الزر التالي خلال 72 ساعة:</p>'
        . '<p style="margin:0 0 18px;text-align:center">'
        . '<a href="' . $safeVerify . '" style="display:inline-block;padding:12px 22px;background:linear-gradient(135deg,#6366f1,#8b5cf6);color:#fff;text-decoration:none;border-radius:12px;font-weight:800">تأكيد البريد الإلكتروني</a>'
        . '</p>'
        . '<p style="margin:0 0 8px;color:#64748b;font-size:13px">إن لم يعمل الزر، انسخ الرابط التالي إلى المتصفح:</p>'
        . '<p style="margin:0 0 16px;word-break:break-all;font-size:12px;direction:ltr;text-align:left;color:#475569">' . $safeVerify . '</p>'
        . '<p style="margin:0;color:#94a3b8;font-size:12px">إذا لم تُنشئ هذا الحساب، تجاهل هذه الرسالة.</p>'
        . '</div>';
}

function activation_send_signup_welcome_email(
    array $config,
    string $toEmail,
    string $fullName,
    string $verifyUrl,
): array {
    $to = strtolower(trim($toEmail));
    if ($to === '' || strpos($to, '@') === false) {
        return ['ok' => false, 'error' => 'validation'];
    }

    $fromEmail = trim((string) ($config['NOTIFY_FROM_EMAIL'] ?? ''));
    if ($fromEmail === '' || strpos($fromEmail, '@') === false) {
        $fromEmail = 'noreply@mizapos.com';
    }
    $fromName = trim((string) ($config['NOTIFY_FROM_NAME'] ?? 'MizaPos'));

    $subject = '=?UTF-8?B?' . base64_encode('مرحباً بك في MizaPos — تأكيد بريدك') . '?=';
    $html = activation_signup_welcome_body_html($config, $fullName, $to, $verifyUrl);

    $headers = [
        'MIME-Version: 1.0',
        'Content-Type: text/html; charset=UTF-8',
        'From: ' . $fromName . ' <' . $fromEmail . '>',
    ];

    $ok = @mail($to, $subject, $html, implode("\r\n", $headers));

    return $ok ? ['ok' => true] : ['ok' => false, 'error' => 'mail_failed'];
}

/**
 * يُصدر رمز تأكيد ويرسل رسالة الترحيب إن لم يكن البريد مؤكداً بعد.
 *
 * @return array{ok:bool,skipped?:bool,error?:string,mail?:array}
 */
function activation_issue_signup_email_verification(
    PDO $pdo,
    array $config,
    string $signupRequestId,
): array {
    $st = $pdo->prepare(
        'SELECT id, email, full_name, email_verified
         FROM signup_requests WHERE id = ? LIMIT 1',
    );
    $st->execute([$signupRequestId]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return ['ok' => false, 'error' => 'not_found'];
    }
    if ((int) ($row['email_verified'] ?? 0) === 1) {
        return ['ok' => true, 'skipped' => true];
    }

    $token = activation_signup_email_token();
    $expires = activation_signup_verify_expires_iso();
    $now = activation_now_iso();
    $verifyUrl = activation_signup_verify_page_url($config, $token);

    $up = $pdo->prepare(
        'UPDATE signup_requests SET
           email_verify_token = ?,
           email_verify_expires_at = ?,
           email_welcome_sent_at = ?
         WHERE id = ?',
    );
    $up->execute([$token, $expires, $now, $signupRequestId]);

    $email = strtolower(trim((string) $row['email']));
    $fullName = trim((string) ($row['full_name'] ?? ''));
    $mail = activation_send_signup_welcome_email($config, $email, $fullName, $verifyUrl);

    return ['ok' => (bool) ($mail['ok'] ?? false), 'mail' => $mail];
}

/**
 * @return array{ok:bool,error?:string,email?:string}
 */
function activation_verify_signup_email_token(PDO $pdo, string $token): array
{
    $token = trim($token);
    if ($token === '' || strlen($token) < 32) {
        return ['ok' => false, 'error' => 'invalid_token'];
    }
    $now = activation_now_iso();
    $st = $pdo->prepare(
        'SELECT id, email, email_verified, email_verify_expires_at
         FROM signup_requests
         WHERE email_verify_token = ?
         LIMIT 1',
    );
    $st->execute([$token]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return ['ok' => false, 'error' => 'invalid_token'];
    }
    if ((int) ($row['email_verified'] ?? 0) === 1) {
        return [
            'ok' => true,
            'email' => strtolower(trim((string) $row['email'])),
            'alreadyVerified' => true,
        ];
    }
    $exp = trim((string) ($row['email_verify_expires_at'] ?? ''));
    if ($exp !== '' && strcmp($now, $exp) > 0) {
        return ['ok' => false, 'error' => 'expired'];
    }

    $up = $pdo->prepare(
        'UPDATE signup_requests SET
           email_verified = 1,
           email_verify_token = NULL,
           email_verify_expires_at = NULL
         WHERE id = ?',
    );
    $up->execute([(string) $row['id']]);

    return [
        'ok' => true,
        'email' => strtolower(trim((string) $row['email'])),
    ];
}
