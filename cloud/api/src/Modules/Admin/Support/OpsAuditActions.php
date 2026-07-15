<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Admin\Support;

/**
 * Canonical action catalog for Ops Audit Log.
 */
final class OpsAuditActions
{
    // Authentication
    public const LOGIN = 'auth.login';
    public const LOGOUT = 'auth.logout';
    public const LOGIN_FAILED = 'auth.login_failed';
    public const PASSWORD_RESET = 'auth.password_reset';
    public const PASSWORD_CHANGED = 'auth.password_changed';
    public const TOKEN_REFRESH = 'auth.token_refresh';

    // Organization
    public const ORG_CREATED = 'organization.created';
    public const ORG_UPDATED = 'organization.updated';
    public const ORG_DELETED = 'organization.deleted';
    public const ORG_SWITCH = 'organization.switch';
    public const ORG_MISMATCH = 'organization.mismatch';

    // Users
    public const USER_CREATED = 'user.created';
    public const USER_UPDATED = 'user.updated';
    public const USER_DELETED = 'user.deleted';
    public const ROLE_CHANGED = 'user.role_changed';
    public const PERMISSION_CHANGED = 'user.permission_changed';

    // Devices
    public const DEVICE_ACTIVATION = 'device.activation';
    public const DEVICE_REVOCATION = 'device.revocation';
    public const DEVICE_LIMIT_REACHED = 'device.limit_reached';

    // License
    public const LICENSE_PULL = 'license.pull';
    public const LICENSE_ACTIVATED = 'license.activated';
    public const LICENSE_EXPIRED = 'license.expired';
    public const SUBSCRIPTION_UPDATED = 'license.subscription_updated';

    // Synchronization
    public const SYNC_STARTED = 'sync.started';
    public const SYNC_FINISHED = 'sync.finished';
    public const SYNC_FAILED = 'sync.failed';
    public const PARTIAL_SYNC = 'sync.partial';
    public const PUSH_STARTED = 'sync.push_started';
    public const PUSH_FINISHED = 'sync.push_finished';
    public const PULL_STARTED = 'sync.pull_started';
    public const PULL_FINISHED = 'sync.pull_finished';
    public const CURSOR_RESET = 'sync.cursor_reset';
    public const TENANT_BIND = 'sync.tenant_bind';
    public const GLOBAL_SYNC_LOCK_BUSY = 'sync.global_lock_busy';
    public const SYNC_TIMEOUT = 'sync.timeout';

    // Inventory
    public const PRODUCT_ADDED = 'inventory.product_added';
    public const PRODUCT_UPDATED = 'inventory.product_updated';
    public const PRODUCT_DELETED = 'inventory.product_deleted';

    // Invoices
    public const INVOICE_CREATED = 'invoice.created';
    public const INVOICE_UPDATED = 'invoice.updated';
    public const INVOICE_DELETED = 'invoice.deleted';
    public const INVOICE_SYNCED = 'invoice.synced';

    // Security
    public const UNAUTHORIZED = 'security.unauthorized';
    public const FORBIDDEN = 'security.forbidden';
    public const INVALID_TOKEN = 'security.invalid_token';
    public const SUSPICIOUS = 'security.suspicious_activity';
    public const AUDIT_MUTATION_BLOCKED = 'security.audit_mutation_blocked';

    // System
    public const SETTINGS_CHANGED = 'system.settings_changed';
    public const BACKUP_STARTED = 'system.backup_started';
    public const BACKUP_FINISHED = 'system.backup_finished';
    public const RESTORE_STARTED = 'system.restore_started';
    public const RESTORE_FINISHED = 'system.restore_finished';

    /** @return list<string> */
    public static function all(): array
    {
        return [
            self::LOGIN, self::LOGOUT, self::LOGIN_FAILED, self::PASSWORD_RESET,
            self::PASSWORD_CHANGED, self::TOKEN_REFRESH,
            self::ORG_CREATED, self::ORG_UPDATED, self::ORG_DELETED, self::ORG_SWITCH, self::ORG_MISMATCH,
            self::USER_CREATED, self::USER_UPDATED, self::USER_DELETED, self::ROLE_CHANGED, self::PERMISSION_CHANGED,
            self::DEVICE_ACTIVATION, self::DEVICE_REVOCATION, self::DEVICE_LIMIT_REACHED,
            self::LICENSE_PULL, self::LICENSE_ACTIVATED, self::LICENSE_EXPIRED, self::SUBSCRIPTION_UPDATED,
            self::SYNC_STARTED, self::SYNC_FINISHED, self::SYNC_FAILED, self::PARTIAL_SYNC,
            self::PUSH_STARTED, self::PUSH_FINISHED, self::PULL_STARTED, self::PULL_FINISHED,
            self::CURSOR_RESET, self::TENANT_BIND, self::GLOBAL_SYNC_LOCK_BUSY, self::SYNC_TIMEOUT,
            self::PRODUCT_ADDED, self::PRODUCT_UPDATED, self::PRODUCT_DELETED,
            self::INVOICE_CREATED, self::INVOICE_UPDATED, self::INVOICE_DELETED, self::INVOICE_SYNCED,
            self::UNAUTHORIZED, self::FORBIDDEN, self::INVALID_TOKEN, self::SUSPICIOUS, self::AUDIT_MUTATION_BLOCKED,
            self::SETTINGS_CHANGED, self::BACKUP_STARTED, self::BACKUP_FINISHED,
            self::RESTORE_STARTED, self::RESTORE_FINISHED,
        ];
    }

    public static function severityFor(string $action, string $status = 'success'): string
    {
        if ($status === 'failure' || $status === 'failed') {
            return match (true) {
                str_starts_with($action, 'security.'),
                $action === self::ORG_MISMATCH,
                $action === self::LOGIN_FAILED => 'critical',
                str_starts_with($action, 'sync.') => 'warning',
                default => 'error',
            };
        }

        return match ($action) {
            self::DEVICE_REVOCATION, self::ORG_DELETED, self::PASSWORD_RESET => 'warning',
            default => 'info',
        };
    }
}
