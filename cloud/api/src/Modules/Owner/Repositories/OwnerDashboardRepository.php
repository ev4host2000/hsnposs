<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Owner\Repositories;

use MizaCloud\Core\Database\Repository;
use PDO;

final class OwnerDashboardRepository extends Repository
{
    /** @return list<array<string, mixed>> */
    public function findOwnerAccountsByEmail(string $email): array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT
                u.id::text AS user_id,
                u.company_id::text AS company_id,
                u.default_branch_id::text AS branch_id,
                u.email::text AS email,
                u.full_name,
                u.role,
                u.password_hash,
                u.account_status,
                c.name AS company_name,
                c.status AS company_status
             FROM users u
             INNER JOIN companies c ON c.id = u.company_id
             WHERE u.email = :email
               AND u.deleted_at IS NULL
               AND u.role IN (\'owner\', \'admin\')
             ORDER BY c.name ASC',
        );
        $stmt->execute(['email' => strtolower($email)]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        return is_array($rows) ? $rows : [];
    }

    /** @return array<string, mixed> */
    public function dashboardSummary(string $companyId): array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT
                (SELECT count(*)::int FROM products WHERE company_id = :company_id AND deleted_at IS NULL) AS products_count,
                (SELECT count(*)::int FROM customers WHERE company_id = :company_id AND deleted_at IS NULL) AS customers_count,
                (SELECT count(*)::int FROM devices
                    WHERE company_id = :company_id AND status = \'active\' AND revoked_at IS NULL) AS active_devices,
                (SELECT count(*)::int FROM sales_invoices
                    WHERE company_id = :company_id AND deleted_at IS NULL
                      AND invoice_status = \'posted\'
                      AND invoice_date >= date_trunc(\'day\', now())) AS sales_today_count,
                (SELECT coalesce(sum(total), 0)::numeric FROM sales_invoices
                    WHERE company_id = :company_id AND deleted_at IS NULL
                      AND invoice_status = \'posted\'
                      AND invoice_date >= date_trunc(\'day\', now())) AS sales_today_total,
                (SELECT count(*)::int FROM sales_invoices
                    WHERE company_id = :company_id AND deleted_at IS NULL
                      AND invoice_status = \'posted\'
                      AND invoice_date >= date_trunc(\'month\', now())) AS sales_month_count,
                (SELECT coalesce(sum(total), 0)::numeric FROM sales_invoices
                    WHERE company_id = :company_id AND deleted_at IS NULL
                      AND invoice_status = \'posted\'
                      AND invoice_date >= date_trunc(\'month\', now())) AS sales_month_total',
        );
        $stmt->execute(['company_id' => $companyId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : [];
    }

    /** @return array<string, mixed>|null */
    public function subscriptionInfo(string $companyId): ?array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT
                cs.status,
                cs.current_period_start::text AS current_period_start,
                cs.current_period_end::text AS current_period_end,
                sp.code AS plan_code,
                sp.name AS plan_name,
                sp.max_devices,
                sp.max_branches
             FROM company_subscriptions cs
             INNER JOIN subscription_plans sp ON sp.id = cs.plan_id
             WHERE cs.company_id = :company_id
               AND cs.status IN (\'trial\', \'active\')
             ORDER BY cs.current_period_end DESC
             LIMIT 1',
        );
        $stmt->execute(['company_id' => $companyId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    /** @return list<array<string, mixed>> */
    public function listDevices(string $companyId): array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT
                id::text AS id,
                device_name,
                platform,
                app_version,
                status,
                last_seen_at::text AS last_seen_at,
                revoked_at::text AS revoked_at
             FROM devices
             WHERE company_id = :company_id
             ORDER BY last_seen_at DESC',
        );
        $stmt->execute(['company_id' => $companyId]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        return is_array($rows) ? $rows : [];
    }
}
