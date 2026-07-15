<?php

declare(strict_types=1);

/**
 * Ops Audit Log configuration (additive; does not affect business APIs).
 */
return [
    'enabled' => filter_var($_ENV['AUDIT_ENABLED'] ?? 'true', FILTER_VALIDATE_BOOLEAN),
    'async' => filter_var($_ENV['AUDIT_ASYNC'] ?? 'true', FILTER_VALIDATE_BOOLEAN),
    'retention_days' => (int) ($_ENV['AUDIT_RETENTION_DAYS'] ?? 90),
    'archive_enabled' => filter_var($_ENV['AUDIT_ARCHIVE_ENABLED'] ?? 'true', FILTER_VALIDATE_BOOLEAN),
    'alert_thresholds' => [
        'organization_mismatch' => (int) ($_ENV['AUDIT_ALERT_ORG_MISMATCH'] ?? 3),
        'login_failed' => (int) ($_ENV['AUDIT_ALERT_LOGIN_FAILED'] ?? 10),
        'sync_failed' => (int) ($_ENV['AUDIT_ALERT_SYNC_FAILED'] ?? 20),
        'unauthorized' => (int) ($_ENV['AUDIT_ALERT_UNAUTHORIZED'] ?? 10),
    ],
    'alert_window_minutes' => (int) ($_ENV['AUDIT_ALERT_WINDOW_MINUTES'] ?? 60),
    'export_max_rows' => (int) ($_ENV['AUDIT_EXPORT_MAX_ROWS'] ?? 5000),
];
