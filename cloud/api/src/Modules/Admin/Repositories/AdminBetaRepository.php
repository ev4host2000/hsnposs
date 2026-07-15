<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Admin\Repositories;

use MizaCloud\Core\Database\Repository;
use MizaCloud\Modules\Auth\Support\Uuid;
use PDO;
use PDOException;

final class AdminBetaRepository extends Repository
{
    /** @return list<array<string, mixed>> */
    public function listSignupRequests(?string $status): array
    {
        $sql = 'SELECT
                id::text AS id,
                store_name,
                email::text AS email,
                owner_name,
                phone,
                message,
                desired_plan_code,
                voucher_code,
                status,
                rejection_reason,
                company_id::text AS company_id,
                reviewed_at::text AS reviewed_at,
                created_at::text AS created_at
             FROM beta_signup_requests
             WHERE 1=1';
        $params = [];

        if ($status !== null && $status !== '') {
            $sql .= ' AND status = :status';
            $params['status'] = $status;
        }

        $sql .= ' ORDER BY created_at DESC LIMIT 200';

        $stmt = $this->db->pdo()->prepare($sql);
        $stmt->execute($params);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        return is_array($rows) ? $rows : [];
    }

    /** @return array<string, mixed>|null */
    public function findSignupRequest(string $id): ?array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT * FROM beta_signup_requests WHERE id = :id LIMIT 1',
        );
        $stmt->execute(['id' => $id]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    public function createSignupRequest(
        string $storeName,
        string $email,
        string $ownerName,
        ?string $phone,
        ?string $message,
        string $planCode,
        ?string $voucherCode,
    ): string {
        $id = Uuid::v4();
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO beta_signup_requests (
                id, store_name, email, owner_name, phone, message,
                desired_plan_code, voucher_code, status
             ) VALUES (
                :id, :store_name, :email, :owner_name, :phone, :message,
                :plan_code, :voucher_code, \'pending\'
             )',
        );
        $stmt->execute([
            'id' => $id,
            'store_name' => $storeName,
            'email' => $email,
            'owner_name' => $ownerName,
            'phone' => $phone,
            'message' => $message,
            'plan_code' => $planCode,
            'voucher_code' => $voucherCode,
        ]);

        return $id;
    }

    public function markSignupApproved(string $id, string $companyId): void
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE beta_signup_requests
             SET status = \'approved\', company_id = :company_id,
                 reviewed_at = now(), updated_at = now()
             WHERE id = :id',
        );
        $stmt->execute(['id' => $id, 'company_id' => $companyId]);
    }

    public function markSignupRejected(string $id, string $reason): void
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE beta_signup_requests
             SET status = \'rejected\', rejection_reason = :reason,
                 reviewed_at = now(), updated_at = now()
             WHERE id = :id',
        );
        $stmt->execute(['id' => $id, 'reason' => $reason]);
    }

    public function pendingSignupByEmail(string $email): bool
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT 1 FROM beta_signup_requests
             WHERE email = :email AND status = \'pending\' LIMIT 1',
        );
        $stmt->execute(['email' => $email]);

        return (bool) $stmt->fetchColumn();
    }

    /** @return array<string, mixed>|null */
    public function findVoucherByCode(string $code): ?array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT * FROM activation_vouchers
             WHERE lower(code) = lower(:code) AND is_active = true
             LIMIT 1',
        );
        $stmt->execute(['code' => $code]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    public function incrementVoucherUse(string $voucherId): void
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE activation_vouchers
             SET used_count = used_count + 1
             WHERE id = :id',
        );
        $stmt->execute(['id' => $voucherId]);
    }

    /** @return list<array<string, mixed>> */
    public function listVouchers(): array
    {
        $stmt = $this->db->pdo()->query(
            'SELECT
                id::text AS id,
                code,
                plan_code,
                max_uses,
                used_count,
                expires_at::text AS expires_at,
                is_active,
                notes,
                created_at::text AS created_at
             FROM activation_vouchers
             ORDER BY created_at DESC
             LIMIT 200',
        );
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        return is_array($rows) ? $rows : [];
    }

    public function createVoucher(
        string $code,
        string $planCode,
        int $maxUses,
        ?string $expiresAt,
        ?string $notes,
    ): string {
        $id = Uuid::v4();
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO activation_vouchers (
                id, code, plan_code, max_uses, expires_at, notes, is_active
             ) VALUES (
                :id, :code, :plan_code, :max_uses, :expires_at, :notes, true
             )',
        );
        $stmt->execute([
            'id' => $id,
            'code' => strtoupper(trim($code)),
            'plan_code' => $planCode,
            'max_uses' => max(1, $maxUses),
            'expires_at' => $expiresAt,
            'notes' => $notes,
        ]);

        return $id;
    }

    public function extendSubscriptionPeriod(string $companyId, int $days): bool
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE company_subscriptions
             SET current_period_end = current_period_end + (:days || \' days\')::interval,
                 updated_at = now(),
                 row_version = row_version + 1
             WHERE company_id = :company_id
               AND status IN (\'trial\', \'active\')',
        );
        $stmt->execute([
            'company_id' => $companyId,
            'days' => max(1, $days),
        ]);

        return $stmt->rowCount() > 0;
    }

    public function countSignupRequests(?string $status): int
    {
        $sql = 'SELECT count(*)::int FROM beta_signup_requests WHERE 1=1';
        $params = [];

        if ($status !== null && $status !== '') {
            $sql .= ' AND status = :status';
            $params['status'] = $status;
        }

        $stmt = $this->db->pdo()->prepare($sql);
        $stmt->execute($params);

        return (int) $stmt->fetchColumn();
    }
}
