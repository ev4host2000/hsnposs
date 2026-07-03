<?php
declare(strict_types=1);

function activation_mail_enabled(array $config): bool
{
    $v = strtolower(trim((string) ($config['NOTIFY_ENABLED'] ?? '0')));
    return in_array($v, ['1', 'true', 'yes', 'on'], true);
}

function activation_mail_dry_run(array $config): bool
{
    $v = strtolower(trim((string) ($config['NOTIFY_DRY_RUN'] ?? '1')));
    return in_array($v, ['1', 'true', 'yes', 'on'], true);
}

function activation_send_email(array $config, string $toEmail, string $subject, string $htmlBody): array
{
    $to = trim($toEmail);
    if ($to === '' || strpos($to, '@') === false) {
        return ['ok' => false, 'error' => 'validation'];
    }
    if (!activation_mail_enabled($config)) {
        return ['ok' => false, 'error' => 'disabled'];
    }
    if (activation_mail_dry_run($config)) {
        return ['ok' => true, 'dryRun' => true];
    }

    $fromEmail = trim((string) ($config['NOTIFY_FROM_EMAIL'] ?? ''));
    $fromName = trim((string) ($config['NOTIFY_FROM_NAME'] ?? 'MizaPos'));
    if ($fromEmail === '' || strpos($fromEmail, '@') === false) {
        return ['ok' => false, 'error' => 'from_not_configured'];
    }

    $fromHeader = sprintf('From: %s <%s>', $fromName, $fromEmail);
    $headers = [
        $fromHeader,
        'MIME-Version: 1.0',
        'Content-Type: text/html; charset=UTF-8',
    ];

    $cc = trim((string) ($config['NOTIFY_SUPPORT_CC'] ?? ''));
    if ($cc !== '') {
        $headers[] = 'Cc: ' . $cc;
    }
    $bcc = trim((string) ($config['NOTIFY_SUPPORT_BCC'] ?? ''));
    if ($bcc !== '') {
        $headers[] = 'Bcc: ' . $bcc;
    }

    $ok = @mail($to, $subject, $htmlBody, implode("\r\n", $headers));
    return $ok ? ['ok' => true] : ['ok' => false, 'error' => 'mail_failed'];
}

/**
 * إرسال بريد نموذج الموقع — لا يتطلب NOTIFY_ENABLED (يحاول mail مباشرة).
 */
function activation_send_website_contact_email(
    array $config,
    string $toEmail,
    string $subject,
    string $htmlBody,
    string $replyName,
    string $replyEmail,
): array {
    $to = trim($toEmail);
    if ($to === '' || strpos($to, '@') === false) {
        return ['ok' => false, 'error' => 'validation'];
    }

    $fromEmail = trim((string) ($config['NOTIFY_FROM_EMAIL'] ?? ''));
    if ($fromEmail === '' || strpos($fromEmail, '@') === false) {
        $fromEmail = 'noreply@mizapos.com';
    }
    $fromName = trim((string) ($config['NOTIFY_FROM_NAME'] ?? 'MizaPos Website'));

    $encodedSubject = '=?UTF-8?B?' . base64_encode($subject) . '?=';
    $headers = [
        'MIME-Version: 1.0',
        'Content-Type: text/html; charset=UTF-8',
        'From: ' . $fromName . ' <' . $fromEmail . '>',
        'Reply-To: ' . $replyName . ' <' . $replyEmail . '>',
    ];

    $ok = @mail($to, $encodedSubject, $htmlBody, implode("\r\n", $headers));
    return $ok ? ['ok' => true] : ['ok' => false, 'error' => 'mail_failed'];
}

