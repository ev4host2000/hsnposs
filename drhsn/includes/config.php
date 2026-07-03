<?php
declare(strict_types=1);

/**
 * Loads .env from project root, then getenv() (cPanel Application Manager variables).
 */
function activation_load_env_file(string $path): array
{
    if (!is_readable($path)) {
        return [];
    }
    $out = [];
    foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        $line = trim($line);
        if ($line === '' || strncmp($line, '#', 1) === 0) {
            continue;
        }
        $eq = strpos($line, '=');
        if ($eq === false) {
            continue;
        }
        $k = trim(substr($line, 0, $eq));
        $v = trim(substr($line, $eq + 1));
        if ($v !== '' && ($v[0] === '"' || $v[0] === "'")) {
            $q = $v[0];
            if (strlen($v) >= 2 && substr($v, -1) === $q) {
                $v = substr($v, 1, -1);
            }
        }
        $out[$k] = $v;
    }
    return $out;
}

function activation_normalize_base_path(string $raw): string
{
    $p = trim($raw);
    if ($p === '' || $p === '/') {
        return '';
    }
    $s = $p[0] === '/' ? $p : '/' . $p;
    return rtrim($s, '/');
}

function activation_config(): array
{
    static $cfg = null;
    if (is_array($cfg)) {
        return $cfg;
    }
    $root = dirname(__DIR__);
    $dotEnv = $root . DIRECTORY_SEPARATOR . '.env';
    $plainEnv = $root . DIRECTORY_SEPARATOR . 'env';
    $dotEnvLocal = $root . DIRECTORY_SEPARATOR . '.env.local';
    $file = [];
    if (is_readable($dotEnv)) {
        $file = activation_load_env_file($dotEnv);
    } elseif (is_readable($plainEnv)) {
        /* بعض أنظمة FTP لا تعرض ملفات تبدأ بنقطة — يمكن استخدام اسم الملف env بدلاً من .env */
        $file = activation_load_env_file($plainEnv);
    }
    if (is_readable($dotEnvLocal)) {
        foreach (activation_load_env_file($dotEnvLocal) as $k => $v) {
            $file[$k] = $v;
        }
    }
    $g = static function (string $key, string $default = '') use ($file): string {
        if (array_key_exists($key, $file)) {
            return (string) $file[$key];
        }
        $v = getenv($key);
        return $v !== false && $v !== '' ? (string) $v : $default;
    };

    $dbRel = $g('DATABASE_PATH', 'data/activation-data.db');
    $dbPath = $dbRel;
    if ($dbPath !== '' && ($dbPath[0] !== '/' && !preg_match('#^[A-Za-z]:[\\\\/]#', $dbPath))) {
        $dbPath = $root . DIRECTORY_SEPARATOR . str_replace(['/', '\\'], DIRECTORY_SEPARATOR, $dbRel);
    }

    $cfg = [
        'root' => $root,
        'APP_BASE_PATH' => activation_normalize_base_path($g('APP_BASE_PATH', '')),
        'DATABASE_PATH' => $dbPath,
        'JWT_SECRET' => $g('JWT_SECRET', ''),
        'ADMIN_PASSWORD_HASH' => trim($g('ADMIN_PASSWORD_HASH', '')),
        'REMOTE_SIGNUP_SHARED_SECRET' => trim($g('REMOTE_SIGNUP_SHARED_SECRET', '')),
        /* SETUP_TOKEN: رمز لصفحة setup_once.php — احذفه أو أفرغه بعد الإعداد */
        'SETUP_TOKEN' => trim($g('SETUP_TOKEN', '')),
        /* Expiry notification emails */
        'NOTIFY_ENABLED' => trim($g('NOTIFY_ENABLED', '0')),
        'NOTIFY_DRY_RUN' => trim($g('NOTIFY_DRY_RUN', '1')),
        'NOTIFY_FROM_EMAIL' => trim($g('NOTIFY_FROM_EMAIL', '')),
        'NOTIFY_FROM_NAME' => trim($g('NOTIFY_FROM_NAME', 'MizaPos')),
        'NOTIFY_DAYS' => trim($g('NOTIFY_DAYS', '7,3,1,0')),
        'NOTIFY_SUBJECT' => trim($g('NOTIFY_SUBJECT', 'تنبيه: اشتراك MizaPos على وشك الانتهاء')),
        'NOTIFY_SUPPORT_CC' => trim($g('NOTIFY_SUPPORT_CC', '')),
        'NOTIFY_SUPPORT_BCC' => trim($g('NOTIFY_SUPPORT_BCC', '')),
        'NOTIFY_RENEW_URL_TEMPLATE' => trim($g('NOTIFY_RENEW_URL_TEMPLATE', '')),
        'NOTIFY_SUPPORT_WHATSAPP' => trim($g('NOTIFY_SUPPORT_WHATSAPP', '')),
        'WA_NOTIFY_ENABLED' => trim($g('WA_NOTIFY_ENABLED', '0')),
        'WA_NOTIFY_WEBHOOK_URL' => trim($g('WA_NOTIFY_WEBHOOK_URL', '')),
        'WA_NOTIFY_TOKEN' => trim($g('WA_NOTIFY_TOKEN', '')),
        /* رسائل نموذج اتصل بنا من mizapos.com */
        'WEBSITE_CONTACT_EMAIL' => trim($g('WEBSITE_CONTACT_EMAIL', 'hsnpal99@gmail.com')),
        'PUBLIC_WEBSITE_URL' => trim($g('PUBLIC_WEBSITE_URL', 'https://mizapos.com')),
    ];
    return $cfg;
}
