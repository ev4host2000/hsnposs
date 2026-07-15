<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Admin\Repositories;

use MizaCloud\Core\Database\Repository;
use MizaCloud\Modules\Auth\Support\Uuid;
use PDO;
use PDOException;

final class AdminRepository extends Repository
{
    private const COMPANY_LIST_SQL = 'SELECT
                c.id,
                c.name,
                c.status,
                c.created_at::text AS created_at,
                COALESCE(dev.active_devices, 0) AS active_devices,
                sp.code AS plan_code,
                sp.name AS plan_name,
                sp.max_devices,
                owner.email AS owner_email,
                owner.full_name AS owner_name,
                default_branch.id AS default_branch_id
             FROM companies c
             LEFT JOIN LATERAL (
                SELECT count(*)::int AS active_devices
                FROM devices d
                WHERE d.company_id = c.id
                  AND d.status = \'active\'
                  AND d.revoked_at IS NULL
             ) dev ON true
             LEFT JOIN LATERAL (
                SELECT cs.plan_id
                FROM company_subscriptions cs
                WHERE cs.company_id = c.id
                  AND cs.status IN (\'trial\', \'active\')
                ORDER BY cs.current_period_end DESC
                LIMIT 1
             ) sub ON true
             LEFT JOIN subscription_plans sp ON sp.id = sub.plan_id
             LEFT JOIN LATERAL (
                SELECT u.email, u.full_name
                FROM users u
                WHERE u.company_id = c.id
                  AND u.role = \'owner\'
                  AND u.deleted_at IS NULL
                ORDER BY u.created_at ASC
                LIMIT 1
             ) owner ON true
             LEFT JOIN LATERAL (
                SELECT b.id
                FROM branches b
                WHERE b.company_id = c.id
                  AND b.is_default = true
                ORDER BY b.created_at ASC
                LIMIT 1
             ) default_branch ON true';

    /** @return list<array<string, mixed>> */
    public function listCompanies(?string $search = null): array
    {
        $sql = self::COMPANY_LIST_SQL;
        $params = [];

        if ($search !== null && $search !== '') {
            $sql .= ' WHERE (
                c.name ILIKE :q
                OR owner.email ILIKE :q
                OR c.id::text = :exact
            )';
            $params['q'] = '%' . $search . '%';
            $params['exact'] = $search;
        }

        $sql .= ' ORDER BY c.created_at DESC';

        if ($params === []) {
            $stmt = $this->db->pdo()->query($sql);
        } else {
            $stmt = $this->db->pdo()->prepare($sql);
            $stmt->execute($params);
        }

        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        return is_array($rows) ? $rows : [];
    }

    /** @return array<string, mixed>|null */
    public function findCompany(string $companyId): ?array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT
                c.id,
                c.name,
                c.status,
                c.default_currency_code,
                c.default_locale,
                c.created_at::text AS created_at,
                COALESCE(dev.active_devices, 0) AS active_devices,
                sp.code AS plan_code,
                sp.name AS plan_name,
                sp.max_devices,
                owner.id AS owner_id,
                owner.email AS owner_email,
                owner.full_name AS owner_name,
                default_branch.id AS default_branch_id,
                default_branch.name AS default_branch_name
             FROM companies c
             LEFT JOIN LATERAL (
                SELECT count(*)::int AS active_devices
                FROM devices d
                WHERE d.company_id = c.id
                  AND d.status = \'active\'
                  AND d.revoked_at IS NULL
             ) dev ON true
             LEFT JOIN LATERAL (
                SELECT cs.plan_id
                FROM company_subscriptions cs
                WHERE cs.company_id = c.id
                  AND cs.status IN (\'trial\', \'active\')
                ORDER BY cs.current_period_end DESC
                LIMIT 1
             ) sub ON true
             LEFT JOIN subscription_plans sp ON sp.id = sub.plan_id
             LEFT JOIN LATERAL (
                SELECT u.id, u.email, u.full_name
                FROM users u
                WHERE u.company_id = c.id
                  AND u.role = \'owner\'
                  AND u.deleted_at IS NULL
                ORDER BY u.created_at ASC
                LIMIT 1
             ) owner ON true
             LEFT JOIN LATERAL (
                SELECT b.id, b.name
                FROM branches b
                WHERE b.company_id = c.id
                  AND b.is_default = true
                ORDER BY b.created_at ASC
                LIMIT 1
             ) default_branch ON true
             WHERE c.id = :id
             LIMIT 1',
        );
        $stmt->execute(['id' => $companyId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    /** @return list<array<string, mixed>> */
    public function listDevicesForCompany(string $companyId): array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT
                id,
                company_id,
                installation_id,
                platform,
                device_name,
                os_name,
                app_version,
                status,
                registered_at::text AS registered_at,
                last_seen_at::text AS last_seen_at,
                revoked_at::text AS revoked_at
             FROM devices
             WHERE company_id = :company_id
             ORDER BY registered_at DESC',
        );
        $stmt->execute(['company_id' => $companyId]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        return is_array($rows) ? $rows : [];
    }

    /** @return list<array<string, mixed>> */
    public function listPlans(): array
    {
        $stmt = $this->db->pdo()->query(
            'SELECT id, code, name, max_devices, max_branches
             FROM subscription_plans
             WHERE is_active = true
             ORDER BY max_devices ASC',
        );
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        return is_array($rows) ? $rows : [];
    }

    /** @return array<string, string> */
    public function findPlanByCode(string $code): ?array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT id, code, name, max_devices
             FROM subscription_plans
             WHERE code = :code AND is_active = true
             LIMIT 1',
        );
        $stmt->execute(['code' => $code]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    /**
     * @return array{
     *   company_id: string,
     *   branch_id: string,
     *   user_id: string,
     *   subscription_id: string
     * }
     */
    public function createTenant(
        string $storeName,
        string $email,
        string $ownerName,
        string $passwordHash,
        string $planId,
    ): array {
        $companyId = Uuid::v4();
        $branchId = Uuid::v4();
        $userId = Uuid::v4();
        $subscriptionId = Uuid::v4();
        $pdo = $this->db->pdo();

        try {
            $pdo->beginTransaction();

            $stmt = $pdo->prepare(
                'INSERT INTO companies (id, name, status, default_currency_code, default_locale)
                 VALUES (:id, :name, \'active\', \'SAR\', \'ar\')',
            );
            $stmt->execute(['id' => $companyId, 'name' => $storeName]);

            $stmt = $pdo->prepare(
                'INSERT INTO branches (id, company_id, code, name, is_default, status)
                 VALUES (:id, :company_id, \'MAIN\', \'Main Branch\', true, \'active\')',
            );
            $stmt->execute(['id' => $branchId, 'company_id' => $companyId]);

            $stmt = $pdo->prepare(
                'INSERT INTO users (
                    id, company_id, default_branch_id, username, email, full_name,
                    password_hash, role, account_status
                 ) VALUES (
                    :id, :company_id, :branch_id, :username, :email, :full_name,
                    :password_hash, \'owner\', \'active\'
                 )',
            );
            $stmt->execute([
                'id' => $userId,
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'username' => $email,
                'email' => $email,
                'full_name' => $ownerName,
                'password_hash' => $passwordHash,
            ]);

            $stmt = $pdo->prepare(
                'INSERT INTO user_branch_access (user_id, branch_id, company_id)
                 VALUES (:user_id, :branch_id, :company_id)',
            );
            $stmt->execute([
                'user_id' => $userId,
                'branch_id' => $branchId,
                'company_id' => $companyId,
            ]);

            $stmt = $pdo->prepare(
                'INSERT INTO company_subscriptions (
                    id, company_id, plan_id, status,
                    current_period_start, current_period_end, auto_renew
                 ) VALUES (
                    :id, :company_id, :plan_id, \'active\',
                    now(), now() + interval \'1 year\', true
                 )',
            );
            $stmt->execute([
                'id' => $subscriptionId,
                'company_id' => $companyId,
                'plan_id' => $planId,
            ]);

            $pdo->commit();
        } catch (PDOException $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $e;
        }

        return [
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'user_id' => $userId,
            'subscription_id' => $subscriptionId,
        ];
    }

    public function emailExists(string $email): bool
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT 1 FROM users WHERE email = :email AND deleted_at IS NULL LIMIT 1',
        );
        $stmt->execute(['email' => $email]);

        return (bool) $stmt->fetchColumn();
    }

    /** @return array<string, mixed>|null */
    public function findDevice(string $deviceId): ?array
    {
        $stmt = $this->db->pdo()->prepare('SELECT * FROM devices WHERE id = :id LIMIT 1');
        $stmt->execute(['id' => $deviceId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    public function revokeDevice(string $deviceId): void
    {
        $pdo = $this->db->pdo();

        try {
            $pdo->beginTransaction();

            $stmt = $pdo->prepare(
                'UPDATE devices
                 SET status = \'revoked\', revoked_at = now(), row_version = row_version + 1
                 WHERE id = :id AND revoked_at IS NULL',
            );
            $stmt->execute(['id' => $deviceId]);

            $stmt = $pdo->prepare(
                'UPDATE device_sessions
                 SET revoked_at = now()
                 WHERE device_id = :device_id AND revoked_at IS NULL',
            );
            $stmt->execute(['device_id' => $deviceId]);

            // Access tokens are stored as subject_type='user' and linked via device_session_id
            // (same linkage Logout uses). Do not filter subject_type='device' — that matches no login tokens.
            $stmt = $pdo->prepare(
                'UPDATE api_tokens
                 SET revoked_at = now()
                 WHERE device_session_id IN (
                     SELECT id FROM device_sessions WHERE device_id = :device_id
                 )
                   AND revoked_at IS NULL',
            );
            $stmt->execute(['device_id' => $deviceId]);

            $stmt = $pdo->prepare(
                'UPDATE refresh_tokens rt
                 SET revoked_at = now()
                 FROM device_sessions ds
                 WHERE rt.device_session_id = ds.id
                   AND ds.device_id = :device_id
                   AND rt.revoked_at IS NULL',
            );
            $stmt->execute(['device_id' => $deviceId]);

            $pdo->commit();
        } catch (PDOException $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $e;
        }
    }

    public function updateCompanyStatus(string $companyId, string $status): bool
    {
        $pdo = $this->db->pdo();

        try {
            $pdo->beginTransaction();

            $stmt = $pdo->prepare(
                'UPDATE companies
                 SET status = :status, updated_at = now(), row_version = row_version + 1
                 WHERE id = :id',
            );
            $stmt->execute(['id' => $companyId, 'status' => $status]);
            $updated = $stmt->rowCount() > 0;

            // RAP-P0-02 (company scope, P0-01 philosophy): non-active tenants must lose
            // live access/refresh immediately — including pairing tokens (company_id only).
            if ($updated && in_array($status, ['suspended', 'closed'], true)) {
                $stmt = $pdo->prepare(
                    'UPDATE device_sessions
                     SET revoked_at = now()
                     WHERE company_id = :company_id AND revoked_at IS NULL',
                );
                $stmt->execute(['company_id' => $companyId]);

                $stmt = $pdo->prepare(
                    'UPDATE api_tokens
                     SET revoked_at = now()
                     WHERE company_id = :company_id AND revoked_at IS NULL',
                );
                $stmt->execute(['company_id' => $companyId]);

                $stmt = $pdo->prepare(
                    'UPDATE refresh_tokens
                     SET revoked_at = now()
                     WHERE company_id = :company_id AND revoked_at IS NULL',
                );
                $stmt->execute(['company_id' => $companyId]);
            }

            $pdo->commit();

            return $updated;
        } catch (PDOException $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $e;
        }
    }

    public function updateActiveSubscriptionPlan(string $companyId, string $planId): bool
    {
        $pdo = $this->db->pdo();
        $stmt = $pdo->prepare(
            'UPDATE company_subscriptions
             SET plan_id = :plan_id, updated_at = now(), row_version = row_version + 1
             WHERE company_id = :company_id
               AND status IN (\'trial\', \'active\')',
        );
        $stmt->execute(['company_id' => $companyId, 'plan_id' => $planId]);

        if ($stmt->rowCount() > 0) {
            return true;
        }

        $subscriptionId = Uuid::v4();
        $insert = $pdo->prepare(
            'INSERT INTO company_subscriptions (
                id, company_id, plan_id, status,
                current_period_start, current_period_end, auto_renew
             ) VALUES (
                :id, :company_id, :plan_id, \'active\',
                now(), now() + interval \'1 year\', true
             )',
        );
        $insert->execute([
            'id' => $subscriptionId,
            'company_id' => $companyId,
            'plan_id' => $planId,
        ]);

        return $insert->rowCount() > 0;
    }

    public function resetOwnerPassword(string $companyId, string $passwordHash): bool
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE users
             SET password_hash = :password_hash, updated_at = now(), row_version = row_version + 1
             WHERE company_id = :company_id
               AND role = \'owner\'
               AND deleted_at IS NULL',
        );
        $stmt->execute([
            'company_id' => $companyId,
            'password_hash' => $passwordHash,
        ]);

        return $stmt->rowCount() > 0;
    }

    /**
     * Hard-delete a tenant and related rows in FK-safe order.
     *
     * @return array{deleted: bool, company_id: string, company_name: string}
     */
    public function deleteCompanyCompletely(string $companyId): array
    {
        $company = $this->findCompany($companyId);
        if ($company === null) {
            throw new PDOException('Company not found');
        }

        $pdo = $this->db->pdo();
        $params = ['company_id' => $companyId];

        try {
            $pdo->beginTransaction();

            // Transactional / ledger children first (RESTRICT on users/devices/products).
            $orderedDeletes = [
                'invoice_payment_splits',
                'sales_return_items',
                'purchase_return_items',
                'sales_invoice_items',
                'purchase_invoice_items',
                'sales_returns',
                'purchase_returns',
                'sales_invoices',
                'purchase_invoices',
                'customer_payments',
                'supplier_payments',
                'stock_movements',
                'partner_ledger',
                'cash_transactions',
                'expenses',
                'inventory_adjustments',
                'opening_stocks',
                'sync_conflicts',
                'sync_queue',
                'sync_changelog',
                'cloud_versions',
                'sync_sequence_counters',
                'audit_logs',
                'price_list_items',
                'price_lists',
                'taxes',
                'product_sale_units',
                'products',
                'product_categories',
                'product_units',
                'customers',
                'suppliers',
                'license_device_slots',
                'licenses',
                'company_subscriptions',
                'api_tokens',
                'refresh_tokens',
                'device_sessions',
                'device_settings',
                'password_reset_tokens',
                'email_verification_tokens',
                'user_branch_access',
                'devices',
                'users',
                'branch_settings',
                'organization_settings',
                'branches',
            ];

            // notification_receipts has no company_id — delete via parent notifications.
            if ($this->tableExists($pdo, 'notification_receipts') && $this->tableExists($pdo, 'notifications')) {
                $stmt = $pdo->prepare(
                    'DELETE FROM notification_receipts nr
                     USING notifications n
                     WHERE nr.notification_id = n.id
                       AND n.company_id = :company_id',
                );
                $stmt->execute($params);
            }
            $this->deleteByCompanyIdIfExists($pdo, 'notifications', $companyId);

            foreach ($orderedDeletes as $table) {
                $this->deleteByCompanyIdIfExists($pdo, $table, $companyId);
            }

            // Detach beta signup rows (no FK cascade guaranteed).
            if ($this->tableExists($pdo, 'beta_signup_requests')) {
                $stmt = $pdo->prepare(
                    'UPDATE beta_signup_requests
                     SET company_id = NULL, updated_at = now()
                     WHERE company_id = :company_id',
                );
                $stmt->execute($params);
            }

            $deleteCompany = $pdo->prepare('DELETE FROM companies WHERE id = :company_id');
            $deleteCompany->execute($params);
            if ($deleteCompany->rowCount() < 1) {
                throw new PDOException('Failed to delete company row');
            }

            $pdo->commit();
        } catch (PDOException $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $e;
        }

        return [
            'deleted' => true,
            'company_id' => $companyId,
            'company_name' => (string) ($company['name'] ?? ''),
        ];
    }

    private function deleteByCompanyIdIfExists(PDO $pdo, string $table, string $companyId): void
    {
        if (!$this->tableExists($pdo, $table)) {
            return;
        }

        $stmt = $pdo->prepare("DELETE FROM {$table} WHERE company_id = :company_id");
        $stmt->execute(['company_id' => $companyId]);
    }

    private function tableExists(PDO $pdo, string $table): bool
    {
        static $cache = [];
        if (array_key_exists($table, $cache)) {
            return $cache[$table];
        }

        $stmt = $pdo->prepare(
            'SELECT 1
             FROM information_schema.tables
             WHERE table_schema = current_schema()
               AND table_name = :table_name
             LIMIT 1',
        );
        $stmt->execute(['table_name' => $table]);
        $cache[$table] = (bool) $stmt->fetchColumn();

        return $cache[$table];
    }
}
