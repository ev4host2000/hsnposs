<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

final class CashTransactionsSyncRepository extends SyncRepositorySupport
{
    public const ENTITY_TYPE = 'cash_transaction';

    /**
     * Create-only idempotent upsert for standalone cash box movements.
     *
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function applyCashTransactionLww(
        string $companyId,
        string $branchId,
        string $entityId,
        string $operation,
        array $payload,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        if ($operation !== 'create') {
            throw new \InvalidArgumentException('cash_transaction only supports create');
        }

        $exists = $this->db->pdo()->prepare(
            'SELECT id, company_id, branch_id, transaction_type, amount, description,
                    reference_type, reference_id, transaction_date::text AS transaction_date,
                    created_by_user_id, row_version
             FROM cash_transactions WHERE id = :id LIMIT 1',
        );
        $exists->execute(['id' => $entityId]);
        $existing = $exists->fetch(\PDO::FETCH_ASSOC);
        if (is_array($existing)) {
            return $this->mapRow($existing, $companyId, $branchId);
        }

        $transactionType = strtolower(trim((string) ($payload['transaction_type'] ?? '')));
        $amount = (float) ($payload['amount'] ?? 0);
        $description = (string) ($payload['description'] ?? '');
        $referenceType = isset($payload['reference_type']) && is_string($payload['reference_type'])
            ? trim($payload['reference_type'])
            : null;
        if ($referenceType === '') {
            $referenceType = null;
        }
        $referenceId = isset($payload['reference_id']) && is_string($payload['reference_id'])
            && trim($payload['reference_id']) !== ''
            ? trim($payload['reference_id'])
            : null;
        $transactionDate = (string) ($payload['transaction_date'] ?? gmdate('c'));
        $createdBy = (string) ($payload['created_by_user_id'] ?? '');
        $rowVersion = max(1, $clientRowVersion);

        $insert = $this->db->pdo()->prepare(
            'INSERT INTO cash_transactions (
                id, company_id, branch_id, transaction_type, amount, description,
                reference_type, reference_id, transaction_date, created_by_user_id, row_version
             ) VALUES (
                :id, :company_id, :branch_id, :transaction_type, :amount, :description,
                :reference_type, :reference_id, CAST(:transaction_date AS timestamptz),
                :created_by_user_id, :row_version
             )
             ON CONFLICT (id) DO NOTHING
             RETURNING id, company_id, branch_id, transaction_type, amount, description,
                       reference_type, reference_id, transaction_date::text AS transaction_date,
                       created_by_user_id, row_version',
        );
        $insert->execute([
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'transaction_type' => $transactionType,
            'amount' => $amount,
            'description' => $description,
            'reference_type' => $referenceType,
            'reference_id' => $referenceId,
            'transaction_date' => $transactionDate,
            'created_by_user_id' => $createdBy,
            'row_version' => $rowVersion,
        ]);
        $row = $insert->fetch(\PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            // Race: another writer inserted first — re-read.
            $exists->execute(['id' => $entityId]);
            $existing = $exists->fetch(\PDO::FETCH_ASSOC);
            if (!is_array($existing)) {
                throw new \RuntimeException('Cash transaction insert failed');
            }

            return $this->mapRow($existing, $companyId, $branchId);
        }

        return $this->mapRow($row, $companyId, $branchId);
    }

    /**
     * @param array<string, mixed> $row
     * @return array<string, mixed>
     */
    private function mapRow(array $row, string $companyId, string $branchId): array
    {
        return [
            'id' => (string) $row['id'],
            'company_id' => (string) ($row['company_id'] ?? $companyId),
            'branch_id' => (string) ($row['branch_id'] ?? $branchId),
            'transaction_type' => (string) $row['transaction_type'],
            'amount' => (float) $row['amount'],
            'description' => (string) ($row['description'] ?? ''),
            'reference_type' => $row['reference_type'] !== null ? (string) $row['reference_type'] : null,
            'reference_id' => $row['reference_id'] !== null ? (string) $row['reference_id'] : null,
            'transaction_date' => (string) $row['transaction_date'],
            'created_by_user_id' => (string) $row['created_by_user_id'],
            'row_version' => (int) ($row['row_version'] ?? 1),
            'deleted' => false,
        ];
    }
}
