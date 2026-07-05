<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Catalog\Support;

use MizaCloud\Modules\Auth\Support\Uuid;
use PDO;
use PDOException;
use RuntimeException;

/**
 * Shared REST CRUD for customers and suppliers tables.
 */
trait CatalogPartnerSupport
{
    /**
     * @param array<string, mixed> $filters
     * @return array{items: list<array<string, mixed>>, total_count: int}
     */
    public function listCustomers(string $companyId, string $branchId, array $filters): array
    {
        return $this->listPartnerTable(
            'customers',
            'customer_number',
            $companyId,
            $branchId,
            $filters,
        );
    }

    /** @return array<string, mixed>|null */
    public function getCustomer(string $companyId, string $id, bool $includeDeleted = false): ?array
    {
        return $this->getPartnerRow('customers', 'customer_number', $companyId, $id, $includeDeleted);
    }

    /**
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    public function createCustomer(
        string $companyId,
        string $branchId,
        string $id,
        array $data,
    ): array {
        return $this->createPartnerRow('customers', 'customer_number', $companyId, $branchId, $id, $data);
    }

    /**
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    public function updateCustomer(string $companyId, string $id, array $data): array
    {
        return $this->updatePartnerRow('customers', 'customer_number', $companyId, $id, $data);
    }

    /** @return array<string, mixed> */
    public function softDeleteCustomer(string $companyId, string $id): array
    {
        return $this->softDeletePartnerRow('customers', $companyId, $id);
    }

    /**
     * @param array<string, mixed> $filters
     * @return array{items: list<array<string, mixed>>, total_count: int}
     */
    public function listSuppliers(string $companyId, string $branchId, array $filters): array
    {
        return $this->listPartnerTable(
            'suppliers',
            'supplier_number',
            $companyId,
            $branchId,
            $filters,
        );
    }

    /** @return array<string, mixed>|null */
    public function getSupplier(string $companyId, string $id, bool $includeDeleted = false): ?array
    {
        return $this->getPartnerRow('suppliers', 'supplier_number', $companyId, $id, $includeDeleted);
    }

    /**
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    public function createSupplier(
        string $companyId,
        string $branchId,
        string $id,
        array $data,
    ): array {
        return $this->createPartnerRow('suppliers', 'supplier_number', $companyId, $branchId, $id, $data);
    }

    /**
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    public function updateSupplier(string $companyId, string $id, array $data): array
    {
        return $this->updatePartnerRow('suppliers', 'supplier_number', $companyId, $id, $data);
    }

    /** @return array<string, mixed> */
    public function softDeleteSupplier(string $companyId, string $id): array
    {
        return $this->softDeletePartnerRow('suppliers', $companyId, $id);
    }

    /**
     * @param array<string, mixed> $filters
     * @return array{items: list<array<string, mixed>>, total_count: int}
     */
    private function listPartnerTable(
        string $table,
        string $numberColumn,
        string $companyId,
        string $branchId,
        array $filters,
    ): array {
        return $this->listFromTable(
            $table,
            $companyId,
            $branchId,
            $filters,
            fn (array $row): array => $this->mapPartnerRow($row, $numberColumn),
            'name ASC',
        );
    }

    /** @return array<string, mixed>|null */
    private function getPartnerRow(
        string $table,
        string $numberColumn,
        string $companyId,
        string $id,
        bool $includeDeleted,
    ): ?array {
        $row = $this->getRow($table, $companyId, $id, $includeDeleted);

        return $row === null ? null : $this->mapPartnerRow($row, $numberColumn);
    }

    /**
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    private function createPartnerRow(
        string $table,
        string $numberColumn,
        string $companyId,
        string $branchId,
        string $id,
        array $data,
    ): array {
        $name = trim((string) ($data['name'] ?? ''));
        $partnerNumber = $this->optionalPartnerString(
            $data['partner_number'] ?? $data[$numberColumn] ?? null,
        );

        $stmt = $this->db->pdo()->prepare(
            "INSERT INTO {$table} (
                id, company_id, branch_id, {$numberColumn}, name, phone, address, notes,
                credit_limit, overdue_alert_days, row_version, created_at, updated_at, deleted_at
             ) VALUES (
                :id, :company_id, :branch_id, :partner_number, :name, :phone, :address, :notes,
                :credit_limit, :overdue_alert_days, 1, now(), now(), NULL
             )
             RETURNING *",
        );
        $stmt->execute([
            'id' => $id,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'partner_number' => $partnerNumber,
            'name' => $name,
            'phone' => $this->optionalPartnerString($data['phone'] ?? null),
            'address' => $this->optionalPartnerString($data['address'] ?? null),
            'notes' => $this->optionalPartnerString($data['notes'] ?? null),
            'credit_limit' => (float) ($data['credit_limit'] ?? 0),
            'overdue_alert_days' => isset($data['overdue_alert_days'])
                ? (int) $data['overdue_alert_days']
                : null,
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new RuntimeException("Partner create failed for {$table}");
        }

        return $this->mapPartnerRow($row, $numberColumn);
    }

    /**
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    private function updatePartnerRow(
        string $table,
        string $numberColumn,
        string $companyId,
        string $id,
        array $data,
    ): array {
        $fields = [];
        $params = ['id' => $id, 'company_id' => $companyId];

        if (array_key_exists('name', $data)) {
            $fields[] = 'name = :name';
            $params['name'] = trim((string) $data['name']);
        }
        if (array_key_exists('partner_number', $data) || array_key_exists($numberColumn, $data)) {
            $fields[] = "{$numberColumn} = :partner_number";
            $params['partner_number'] = $this->optionalPartnerString(
                $data['partner_number'] ?? $data[$numberColumn] ?? null,
            );
        }
        if (array_key_exists('phone', $data)) {
            $fields[] = 'phone = :phone';
            $params['phone'] = $this->optionalPartnerString($data['phone']);
        }
        if (array_key_exists('address', $data)) {
            $fields[] = 'address = :address';
            $params['address'] = $this->optionalPartnerString($data['address']);
        }
        if (array_key_exists('notes', $data)) {
            $fields[] = 'notes = :notes';
            $params['notes'] = $this->optionalPartnerString($data['notes']);
        }
        if (array_key_exists('credit_limit', $data)) {
            $fields[] = 'credit_limit = :credit_limit';
            $params['credit_limit'] = (float) $data['credit_limit'];
        }
        if (array_key_exists('overdue_alert_days', $data)) {
            $fields[] = 'overdue_alert_days = :overdue_alert_days';
            $params['overdue_alert_days'] = $data['overdue_alert_days'] !== null
                ? (int) $data['overdue_alert_days']
                : null;
        }

        if ($fields === []) {
            $existing = $this->getPartnerRow($table, $numberColumn, $companyId, $id);
            if ($existing === null) {
                throw new RuntimeException('Partner not found');
            }

            return $existing;
        }

        $fields[] = 'updated_at = now()';
        $fields[] = 'deleted_at = NULL';

        $stmt = $this->db->pdo()->prepare(
            "UPDATE {$table} SET " . implode(', ', $fields) . '
             WHERE id = :id AND company_id = :company_id AND deleted_at IS NULL
             RETURNING *',
        );
        $stmt->execute($params);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new RuntimeException('Partner update failed');
        }

        return $this->mapPartnerRow($row, $numberColumn);
    }

    /** @return array<string, mixed> */
    private function softDeletePartnerRow(string $table, string $companyId, string $id): array
    {
        return $this->softDeleteRow($table, $companyId, $id);
    }

    /** @param array<string, mixed> $row @return array<string, mixed> */
    private function mapPartnerRow(array $row, string $numberColumn): array
    {
        return [
            'id' => (string) $row['id'],
            'company_id' => (string) $row['company_id'],
            'branch_id' => (string) $row['branch_id'],
            'name' => (string) $row['name'],
            'phone' => $row['phone'],
            'address' => $row['address'],
            'notes' => $row['notes'],
            'partner_number' => $row[$numberColumn],
            'credit_limit' => (float) ($row['credit_limit'] ?? 0),
            'overdue_alert_days' => $row['overdue_alert_days'] !== null
                ? (int) $row['overdue_alert_days']
                : null,
            'row_version' => (int) $row['row_version'],
            'created_at' => $this->formatTimestamp((string) ($row['created_at'] ?? '')),
            'updated_at' => $this->formatTimestamp((string) ($row['updated_at'] ?? '')),
            'deleted_at' => $row['deleted_at'] !== null
                ? $this->formatTimestamp((string) $row['deleted_at'])
                : null,
        ];
    }

    private function optionalPartnerString(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }
        $trimmed = trim((string) $value);

        return $trimmed === '' ? null : $trimmed;
    }
}
