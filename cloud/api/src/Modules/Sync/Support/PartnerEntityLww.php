<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Support;

use MizaCloud\Modules\Sync\Repositories\SyncRepositorySupport;

/**
 * Shared LWW upsert/soft-delete for customers and suppliers sync repositories.
 */
trait PartnerEntityLww
{
    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    protected function applyPartnerLww(
        string $table,
        string $numberColumn,
        string $companyId,
        string $branchId,
        string $entityId,
        string $operation,
        array $payload,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        /** @var SyncRepositorySupport $this */
        if ($operation === 'delete') {
            $deleted = $this->softDeleteRow($table, $companyId, $entityId, $clientRowVersion);

            return [
                'id' => $entityId,
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'row_version' => $deleted['row_version'],
                'deleted' => true,
            ];
        }

        $name = trim((string) ($payload['name'] ?? ''));
        $phone = $this->optionalString($payload['phone'] ?? null);
        $address = $this->optionalString($payload['address'] ?? null);
        $notes = $this->optionalString($payload['notes'] ?? null);
        $partnerNumber = $this->optionalString(
            $payload['partner_number']
            ?? $payload[$numberColumn]
            ?? null,
        );
        $creditLimit = (float) ($payload['credit_limit'] ?? 0);
        $overdueAlertDays = isset($payload['overdue_alert_days'])
            ? (int) $payload['overdue_alert_days']
            : null;
        $groupId = $this->optionalString(
            $payload['customer_group_id'] ?? $payload['supplier_group_id'] ?? null,
        );

        $groupColumn = $table === 'customers' ? 'customer_group_id' : 'supplier_group_id';
        $hasGroupColumn = $this->partnerTableHasColumn($table, $groupColumn);

        $columns = [
            'id', 'company_id', 'branch_id', $numberColumn, 'name', 'phone', 'address', 'notes',
            'credit_limit', 'overdue_alert_days', 'origin_device_id',
            'row_version', 'created_at', 'updated_at', 'deleted_at',
        ];
        $values = [
            ':id', ':company_id', ':branch_id', ':partner_number', ':name', ':phone', ':address', ':notes',
            ':credit_limit', ':overdue_alert_days', ':origin_device_id',
            ':row_version', 'now()', 'now()', 'NULL',
        ];
        $updates = [
            "{$numberColumn} = EXCLUDED.{$numberColumn}",
            'name = EXCLUDED.name',
            'phone = EXCLUDED.phone',
            'address = EXCLUDED.address',
            'notes = EXCLUDED.notes',
            'credit_limit = EXCLUDED.credit_limit',
            'overdue_alert_days = EXCLUDED.overdue_alert_days',
            'origin_device_id = COALESCE(EXCLUDED.origin_device_id, ' . $table . '.origin_device_id)',
            'row_version = GREATEST(' . $table . '.row_version, EXCLUDED.row_version)',
            'updated_at = now()',
            'deleted_at = NULL',
        ];

        if ($hasGroupColumn) {
            $columns[] = $groupColumn;
            $values[] = ':group_id';
            $updates[] = "{$groupColumn} = EXCLUDED.{$groupColumn}";
        }

        $returnColumns = 'row_version, name, phone, address, notes, credit_limit, overdue_alert_days, ' . $numberColumn;
        if ($hasGroupColumn) {
            $returnColumns .= ', ' . $groupColumn;
        }

        $sql = 'INSERT INTO ' . $table . ' (' . implode(', ', $columns) . ')
             VALUES (' . implode(', ', $values) . ')
             ON CONFLICT (id) DO UPDATE SET ' . implode(', ', $updates) . '
             RETURNING ' . $returnColumns;

        $stmt = $this->db->pdo()->prepare($sql);
        $params = [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'partner_number' => $partnerNumber,
            'name' => $name,
            'phone' => $phone,
            'address' => $address,
            'notes' => $notes,
            'credit_limit' => $creditLimit,
            'overdue_alert_days' => $overdueAlertDays,
            'origin_device_id' => $originDeviceId,
            'row_version' => max(1, $clientRowVersion),
        ];
        if ($hasGroupColumn) {
            $params['group_id'] = $groupId;
        }
        $stmt->execute($params);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new \RuntimeException("Partner upsert failed for {$table}");
        }

        $result = [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'name' => (string) $row['name'],
            'phone' => $row['phone'],
            'address' => $row['address'],
            'notes' => $row['notes'],
            'partner_number' => $row[$numberColumn],
            'credit_limit' => (float) $row['credit_limit'],
            'overdue_alert_days' => $row['overdue_alert_days'] !== null
                ? (int) $row['overdue_alert_days']
                : null,
            'row_version' => (int) $row['row_version'],
            'deleted' => false,
        ];
        if ($hasGroupColumn && array_key_exists($groupColumn, $row)) {
            $result[$groupColumn] = $row[$groupColumn];
        }

        return $result;
    }

    private function partnerTableHasColumn(string $table, string $column): bool
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT 1 FROM information_schema.columns
             WHERE table_schema = current_schema()
               AND table_name = :table
               AND column_name = :column
             LIMIT 1',
        );
        $stmt->execute(['table' => $table, 'column' => $column]);

        return (bool) $stmt->fetchColumn();
    }

    private function optionalString(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }
        $trimmed = trim((string) $value);

        return $trimmed === '' ? null : $trimmed;
    }
}
