<?php
declare(strict_types=1);

/**
 * استقبال رسائل «اتصل بنا» من mizapos.com
 * يحفظ كل رسالة في data/contact_inbox/ ثم يحاول إرسال بريد.
 */
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header('Content-Type: application/json; charset=utf-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'method_not_allowed'], JSON_UNESCAPED_UNICODE);
    exit;
}

$raw = file_get_contents('php://input');
$body = is_string($raw) && $raw !== '' ? json_decode($raw, true) : null;
if (!is_array($body)) {
    $body = $_POST;
}

if (trim((string) ($body['company'] ?? '')) !== '') {
    echo json_encode(['ok' => true], JSON_UNESCAPED_UNICODE);
    exit;
}

$name = trim((string) ($body['name'] ?? ''));
$email = strtolower(trim((string) ($body['email'] ?? '')));
$phone = trim((string) ($body['phone'] ?? ''));
$topic = trim((string) ($body['topic'] ?? 'استفسار عام'));
$message = trim((string) ($body['message'] ?? ''));

if ($name === '' || $email === '' || strpos($email, '@') === false) {
    http_response_code(400);
    echo json_encode([
        'error' => 'validation',
        'message' => 'الاسم والبريد الإلكتروني مطلوبان.',
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

$msgLen = function_exists('mb_strlen') ? mb_strlen($message) : strlen($message);
if ($msgLen < 8) {
    http_response_code(400);
    echo json_encode([
        'error' => 'validation',
        'message' => 'الرسالة قصيرة جداً (8 أحرف على الأقل).',
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

$toEmail = 'hsnpal99@gmail.com';
$record = [
    'id' => date('Ymd-His') . '-' . bin2hex(random_bytes(4)),
    'createdAt' => gmdate('c'),
    'name' => $name,
    'email' => $email,
    'phone' => $phone,
    'topic' => $topic,
    'message' => $message,
    'ip' => (string) ($_SERVER['REMOTE_ADDR'] ?? ''),
    'userAgent' => (string) ($_SERVER['HTTP_USER_AGENT'] ?? ''),
];

$inboxDir = __DIR__ . '/data/contact_inbox';
if (!is_dir($inboxDir) && !@mkdir($inboxDir, 0755, true) && !is_dir($inboxDir)) {
    http_response_code(500);
    echo json_encode([
        'error' => 'storage_failed',
        'message' => 'تعذّر حفظ الرسالة على الخادم.',
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

$saved = @file_put_contents(
    $inboxDir . '/' . $record['id'] . '.json',
    json_encode($record, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT),
    LOCK_EX,
);

if ($saved === false) {
    http_response_code(500);
    echo json_encode([
        'error' => 'storage_failed',
        'message' => 'تعذّر حفظ الرسالة على الخادم.',
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

$subjectRaw = 'MizaPos.com — ' . $topic;
$subject = '=?UTF-8?B?' . base64_encode($subjectRaw) . '?=';

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
    . '<p style="font-size:12px;color:#64748b">معرّف: ' . htmlspecialchars($record['id'], ENT_QUOTES, 'UTF-8') . '</p>'
    . '</div>';

$textBody = "موضوع: $topic\nالاسم: $name\nالبريد: $email\nالهاتف: $phone\n\n$message\n\nID: {$record['id']}";

$fromEmail = 'noreply@mizapos.com';
$headers = [
    'MIME-Version: 1.0',
    'Content-Type: text/html; charset=UTF-8',
    'From: MizaPos Website <' . $fromEmail . '>',
    'Reply-To: ' . $name . ' <' . $email . '>',
    'X-MizaPos-Contact-Id: ' . $record['id'],
];

$mailSent = @mail($toEmail, $subject, $html, implode("\r\n", $headers));

if (!$mailSent) {
  // محاولة ثانية كنص عادي (بعض الاستضافات ترفض HTML)
    $headersText = [
        'Content-Type: text/plain; charset=UTF-8',
        'From: MizaPos Website <' . $fromEmail . '>',
        'Reply-To: ' . $name . ' <' . $email . '>',
    ];
    $mailSent = @mail($toEmail, $subjectRaw, $textBody, implode("\r\n", $headersText));
}

echo json_encode([
    'ok' => true,
    'mailSent' => $mailSent,
    'id' => $record['id'],
], JSON_UNESCAPED_UNICODE);
