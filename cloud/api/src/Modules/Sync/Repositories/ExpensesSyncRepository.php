<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

final class ExpensesSyncRepository extends SyncRepositorySupport
{
    public const ENTITY_TYPE = 'expense';

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function applyExpenseLww(
        string $companyId,
        string $branchId,
        string $entityId,
        string $operation,
        array $payload,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        if ($operation === 'delete') {
            $stmt = $this->db->pdo()->prepare(
                'UPDATE expenses
                 SET deleted_at = now(),
                     row_version = GREATEST(row_version, :row_version),
                     updated_at = now()
                 WHERE id = :id AND company_id = :company_id
                 RETURNING row_version',
            );
            $stmt->execute([
                'id' => $entityId,
                'company_id' => $companyId,
                'row_version' => max(1, $clientRowVersion),
            ]);
            $row = $stmt->fetch(\PDO::FETCH_ASSOC);

            return [
                'id' => $entityId,
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'row_version' => (int) ($row['row_version'] ?? max(1, $clientRowVersion)),
                'deleted' => true,
            ];
        }

        $title = trim((string) ($payload['title'] ?? ''));
        $amount = (float) ($payload['amount'] ?? 0);
        $notes = isset($payload['notes']) && is_string($payload['notes'])
            ? trim($payload['notes'])
            : null;
        if ($notes === '') {
            $notes = null;
        }
        $expenseDate = (string) ($payload['expense_date'] ?? gmdate('c'));
        $createdBy = (string) ($payload['created_by_user_id'] ?? '');
        $rowVersion = max(1, $clientRowVersion);

        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO expenses (
                id, company_id, branch_id, title, amount, expense_date, notes,
                created_by_user_id, origin_device_id, row_version, created_at, updated_at, deleted_at
             ) VALUES (
                :id, :company_id, :branch_id, :title, :amount, CAST(:expense_date AS timestamptz), :notes,
                :created_by_user_id, :origin_device_id, :row_version, now(), now(), NULL
             )
             ON CONFLICT (id) DO UPDATE SET
                title = EXCLUDED.title,
                amount = EXCLUDED.amount,
                expense_date = EXCLUDED.expense_date,
                notes = EXCLUDED.notes,
                created_by_user_id = EXCLUDED.created_by_user_id,
                origin_device_id = COALESCE(EXCLUDED.origin_device_id, expenses.origin_device_id),
                row_version = GREATEST(expenses.row_version, EXCLUDED.row_version),
                updated_at = now(),
                deleted_at = NULL
             RETURNING id, company_id, branch_id, title, amount, expense_date::text AS expense_date,
                       notes, created_by_user_id, row_version',
        );
        $stmt->execute([
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'title' => $title,
            'amount' => $amount,
            'expense_date' => $expenseDate,
            'notes' => $notes,
            'created_by_user_id' => $createdBy,
            'origin_device_id' => $originDeviceId,
            'row_version' => $rowVersion,
        ]);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new \RuntimeException('Expense upsert failed');
        }

        return [
            'id' => (string) $row['id'],
            'company_id' => (string) $row['company_id'],
            'branch_id' => (string) $row['branch_id'],
            'title' => (string) $row['title'],
            'amount' => (float) $row['amount'],
            'expense_date' => (string) $row['expense_date'],
            'notes' => $row['notes'] !== null ? (string) $row['notes'] : null,
            'created_by_user_id' => (string) $row['created_by_user_id'],
            'row_version' => (int) $row['row_version'],
            'deleted' => false,
        ];
    }
}
