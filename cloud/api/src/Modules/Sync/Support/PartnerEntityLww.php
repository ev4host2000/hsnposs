<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Support;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Modules\Sync\Repositories\SyncRepositorySupport;

/**
 * Shared catalog apply for customers and suppliers — mirrors Products golden path.
 * Update/patch never full-overwrite; create is full insert; delete is version-gated.
 */
trait PartnerEntityLww
{
    abstract protected function partnerPatchOrchestrator(): CatalogPatchOrchestrator;

    abstract protected function partnerEntityType(): string;

    abstract protected function partnerEntityPath(): string;

    abstract protected function partnerTable(): string;

    abstract protected function partnerNumberColumn(): string;

    /**
     * @param array<string, mixed> $payload
     * @param array<string, mixed> $event
     * @return array<string, mixed>
     */
    protected function applyPartnerLww(
        string $companyId,
        string $branchId,
        string $entityId,
        string $operation,
        array $payload,
        int $clientRowVersion,
        ?string $originDeviceId,
        array $event = [],
    ): array {
        $operation = strtolower(trim($operation));
        if ($operation === 'delete') {
            return $this->applyPartnerDelete(
                $companyId,
                $branchId,
                $entityId,
                $clientRowVersion,
                $originDeviceId,
                $event,
            );
        }

        if ($operation === 'patch') {
            return $this->applyPartnerPatchUpdate(
                $companyId,
                $branchId,
                $entityId,
                $operation,
                $payload,
                $clientRowVersion,
                $originDeviceId,
                $event,
            );
        }

        if ($operation !== 'create' && $operation !== 'update') {
            $operation = 'update';
        }

        if ($operation === 'create') {
            return $this->applyPartnerCreate(
                $companyId,
                $branchId,
                $entityId,
                $payload,
                $clientRowVersion,
                $originDeviceId,
                $event,
            );
        }

        $existing = $this->fetchPartnerRow($companyId, $entityId);
        if ($existing === null) {
            return $this->applyPartnerCreate(
                $companyId,
                $branchId,
                $entityId,
                $payload,
                $clientRowVersion,
                $originDeviceId,
                $event,
            );
        }

        return $this->applyPartnerPatchUpdate(
            $companyId,
            $branchId,
            $entityId,
            $operation,
            $payload,
            $clientRowVersion,
            $originDeviceId,
            $event,
            $existing,
        );
    }

    /**
     * @param array<string, mixed> $payload
     * @param array<string, mixed> $event
     * @param array<string, mixed>|null $existing
     * @return array<string, mixed>
     */
    private function applyPartnerPatchUpdate(
        string $companyId,
        string $branchId,
        string $entityId,
        string $operation,
        array $payload,
        int $clientRowVersion,
        ?string $originDeviceId,
        array $event,
        ?array $existing = null,
    ): array {
        $existing ??= $this->fetchPartnerRow($companyId, $entityId);
        if ($existing === null) {
            throw new HttpException(
                'version_conflict',
                'Partner patch rejected: entity not found',
                409,
            );
        }

        $payload = $this->normalizePartnerPayloadAliases($payload);

        try {
            $plan = $this->partnerPatchOrchestrator()->planUpdate(
                $this->partnerEntityType(),
                $this->partnerEntityPath(),
                $entityId,
                $operation,
                $event,
                $payload,
                $existing,
                max(1, $clientRowVersion),
            );
        } catch (\InvalidArgumentException $e) {
            throw new HttpException('validation_error', $e->getMessage(), 400);
        }

        if ($plan['decision'] === 'validation_error') {
            throw new HttpException('validation_error', 'Patch validation failed', 400, [
                'fields' => $plan['errors'],
            ]);
        }

        if ($plan['decision'] === CatalogVersionGate::DECISION_CONFLICT) {
            throw new HttpException(
                'version_conflict',
                'Partner update rejected: stale or conflicting base_row_version',
                409,
            );
        }

        if ($plan['decision'] === CatalogVersionGate::DECISION_NO_OP) {
            return $this->partnerEnvelopeFromRow(
                $companyId,
                $branchId,
                $entityId,
                $existing,
                deleted: ($existing['deleted_at'] ?? null) !== null,
                noOp: true,
            );
        }

        $fields = $plan['normalized_changed_fields'];
        if ($fields === []) {
            return $this->partnerEnvelopeFromRow(
                $companyId,
                $branchId,
                $entityId,
                $existing,
                deleted: false,
                noOp: true,
            );
        }

        $row = $this->executePartnerPatch(
            $companyId,
            $entityId,
            $fields,
            (int) $plan['new_row_version'],
            $originDeviceId,
            (int) ($existing['row_version'] ?? 1),
        );

        return $this->partnerEnvelopeFromRow(
            $companyId,
            $branchId,
            $entityId,
            $row,
            deleted: false,
            noOp: false,
        );
    }

    /**
     * @param array<string, mixed> $fields
     * @return array<string, mixed>
     */
    private function executePartnerPatch(
        string $companyId,
        string $entityId,
        array $fields,
        int $newRowVersion,
        ?string $originDeviceId,
        int $expectedServerVersion,
    ): array {
        $table = $this->partnerTable();
        $numberColumn = $this->partnerNumberColumn();
        $groupColumn = $table === 'customers' ? 'customer_group_id' : 'supplier_group_id';
        $hasGroupColumn = $this->partnerTableHasColumn($table, $groupColumn);

        $setParts = [];
        $params = [
            'id' => $entityId,
            'company_id' => $companyId,
            'new_row_version' => $newRowVersion,
            'expected_version' => $expectedServerVersion,
            'origin_device_id' => $originDeviceId,
        ];

        foreach ($fields as $name => $value) {
            $column = match ($name) {
                'partner_number' => $numberColumn,
                'customer_group_id', 'supplier_group_id' => $groupColumn,
                default => $name,
            };

            if (in_array($column, ['customer_group_id', 'supplier_group_id'], true) && !$hasGroupColumn) {
                continue;
            }

            $allowed = [
                $numberColumn,
                'name',
                'phone',
                'address',
                'notes',
                'credit_limit',
                'overdue_alert_days',
            ];
            if ($hasGroupColumn) {
                $allowed[] = $groupColumn;
            }
            if (!in_array($column, $allowed, true)) {
                throw new HttpException(
                    'validation_error',
                    'Forbidden or unknown patch column: ' . $name,
                    400,
                );
            }

            $param = 'f_' . preg_replace('/[^a-z0-9_]/', '_', $column);
            $setParts[] = "{$column} = :{$param}";
            $params[$param] = $value;
        }

        if ($setParts === []) {
            $existing = $this->fetchPartnerRow($companyId, $entityId);
            if ($existing === null) {
                throw new HttpException('version_conflict', 'Partner patch rejected: entity not found', 409);
            }

            return $existing;
        }

        $setParts[] = 'row_version = :new_row_version';
        $setParts[] = 'origin_device_id = COALESCE(:origin_device_id, ' . $table . '.origin_device_id)';
        $setParts[] = 'updated_at = now()';
        $setParts[] = 'deleted_at = NULL';

        $returnColumns = 'row_version, name, phone, address, notes, credit_limit, overdue_alert_days, '
            . $numberColumn . ', deleted_at';
        if ($hasGroupColumn) {
            $returnColumns .= ', ' . $groupColumn;
        }

        $sql = 'UPDATE ' . $table . ' SET ' . implode(', ', $setParts)
            . ' WHERE id = :id AND company_id = :company_id'
            . ' AND row_version = :expected_version'
            . ' RETURNING ' . $returnColumns;

        $stmt = $this->db->pdo()->prepare($sql);
        $stmt->execute($params);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC);

        if (!is_array($row)) {
            throw new HttpException(
                'version_conflict',
                'Partner update rejected: concurrent version change',
                409,
            );
        }

        return $this->dictionaryShapeFromDbRow($row);
    }

    /**
     * @param array<string, mixed> $payload
     * @param array<string, mixed> $event
     * @return array<string, mixed>
     */
    private function applyPartnerCreate(
        string $companyId,
        string $branchId,
        string $entityId,
        array $payload,
        int $clientRowVersion,
        ?string $originDeviceId,
        array $event,
    ): array {
        $existing = $this->fetchPartnerRow($companyId, $entityId);
        if ($existing !== null) {
            return $this->applyPartnerPatchUpdate(
                $companyId,
                $branchId,
                $entityId,
                'update',
                $payload,
                $clientRowVersion,
                $originDeviceId,
                $event === []
                    ? ['operation_id' => (string) ($payload['operation_id'] ?? $entityId . ':create')]
                    : $event,
                $existing,
            );
        }

        $serverRowVersion = null;
        $decision = CatalogVersionGate::decide(
            CatalogVersionGate::OPERATION_CREATE,
            $serverRowVersion,
            max(1, $clientRowVersion),
            false,
        );

        if ($decision === CatalogVersionGate::DECISION_CONFLICT) {
            throw new HttpException(
                'version_conflict',
                'Partner create rejected: stale or conflicting row_version',
                409,
            );
        }

        $payload = $this->normalizePartnerPayloadAliases($payload);
        $table = $this->partnerTable();
        $numberColumn = $this->partnerNumberColumn();
        $groupColumn = $table === 'customers' ? 'customer_group_id' : 'supplier_group_id';
        $hasGroupColumn = $this->partnerTableHasColumn($table, $groupColumn);

        $name = trim((string) ($payload['name'] ?? ''));
        $phone = $this->optionalString($payload['phone'] ?? null);
        $address = $this->optionalString($payload['address'] ?? null);
        $notes = $this->optionalString($payload['notes'] ?? null);
        $partnerNumber = $this->optionalString($payload['partner_number'] ?? null);
        $creditLimit = (float) ($payload['credit_limit'] ?? 0);
        $overdueAlertDays = array_key_exists('overdue_alert_days', $payload)
            ? ($payload['overdue_alert_days'] === null ? null : (int) $payload['overdue_alert_days'])
            : null;
        $groupId = $this->optionalString($payload[$groupColumn] ?? null);
        $rowVersion = max(1, $clientRowVersion);

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
            'row_version' => $rowVersion,
        ];
        if ($hasGroupColumn) {
            $columns[] = $groupColumn;
            $values[] = ':group_id';
            $params['group_id'] = $groupId;
        }

        $returnColumns = 'row_version, name, phone, address, notes, credit_limit, overdue_alert_days, '
            . $numberColumn . ', deleted_at';
        if ($hasGroupColumn) {
            $returnColumns .= ', ' . $groupColumn;
        }

        $sql = 'INSERT INTO ' . $table . ' (' . implode(', ', $columns) . ')
             VALUES (' . implode(', ', $values) . ')
             RETURNING ' . $returnColumns;

        $stmt = $this->db->pdo()->prepare($sql);
        $stmt->execute($params);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new HttpException('internal_error', 'Partner create failed', 500);
        }

        return $this->partnerEnvelopeFromRow(
            $companyId,
            $branchId,
            $entityId,
            $this->dictionaryShapeFromDbRow($row),
            deleted: false,
            noOp: false,
        );
    }

    /**
     * @param array<string, mixed> $event
     * @return array<string, mixed>
     */
    private function applyPartnerDelete(
        string $companyId,
        string $branchId,
        string $entityId,
        int $clientRowVersion,
        ?string $originDeviceId,
        array $event = [],
    ): array {
        $existing = $this->fetchPartnerRow($companyId, $entityId);
        $serverRowVersion = $existing === null ? null : (int) ($existing['row_version'] ?? 1);
        $alreadyDeleted = $existing !== null && ($existing['deleted_at'] ?? null) !== null;

        $versionForGate = $clientRowVersion;
        if (isset($event['base_row_version']) && is_numeric($event['base_row_version'])) {
            $base = (int) $event['base_row_version'];
            if ($base >= 1 && $serverRowVersion !== null && $base !== $serverRowVersion) {
                throw new HttpException(
                    'version_conflict',
                    'Partner delete rejected: stale or conflicting base_row_version',
                    409,
                );
            }
            $versionForGate = max($clientRowVersion, $base);
        }

        $decision = CatalogVersionGate::decide(
            CatalogVersionGate::OPERATION_DELETE,
            $serverRowVersion,
            max(1, $versionForGate),
            $alreadyDeleted,
        );

        if ($decision === CatalogVersionGate::DECISION_CONFLICT) {
            throw new HttpException(
                'version_conflict',
                'Partner delete rejected: stale or conflicting row_version',
                409,
            );
        }

        if ($decision === CatalogVersionGate::DECISION_NO_OP) {
            if ($existing === null) {
                return [
                    'id' => $entityId,
                    'company_id' => $companyId,
                    'branch_id' => $branchId,
                    'row_version' => max(1, $clientRowVersion),
                    'deleted' => true,
                    'no_op' => true,
                ];
            }

            return $this->partnerEnvelopeFromRow(
                $companyId,
                $branchId,
                $entityId,
                $existing,
                deleted: true,
                noOp: true,
            );
        }

        /** @var SyncRepositorySupport $this */
        $deleted = $this->softDeleteRow(
            $this->partnerTable(),
            $companyId,
            $entityId,
            max(1, $versionForGate),
        );

        return [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'row_version' => $deleted['row_version'],
            'deleted' => true,
            'no_op' => false,
        ];
    }

    /**
     * @return array<string, mixed>|null dictionary-shaped row including row_version
     */
    private function fetchPartnerRow(string $companyId, string $entityId): ?array
    {
        $table = $this->partnerTable();
        $numberColumn = $this->partnerNumberColumn();
        $groupColumn = $table === 'customers' ? 'customer_group_id' : 'supplier_group_id';
        $hasGroupColumn = $this->partnerTableHasColumn($table, $groupColumn);

        $cols = 'id, company_id, branch_id, row_version, name, phone, address, notes, credit_limit,
                 overdue_alert_days, ' . $numberColumn . ', deleted_at, origin_device_id';
        if ($hasGroupColumn) {
            $cols .= ', ' . $groupColumn;
        }

        $stmt = $this->db->pdo()->prepare(
            'SELECT ' . $cols . ' FROM ' . $table
            . ' WHERE id = :id AND company_id = :company_id LIMIT 1',
        );
        $stmt->execute(['id' => $entityId, 'company_id' => $companyId]);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC);

        return is_array($row) ? $this->dictionaryShapeFromDbRow($row) : null;
    }

    /**
     * @param array<string, mixed> $row
     * @return array<string, mixed>
     */
    private function dictionaryShapeFromDbRow(array $row): array
    {
        $numberColumn = $this->partnerNumberColumn();
        $groupColumn = $this->partnerTable() === 'customers' ? 'customer_group_id' : 'supplier_group_id';

        $shaped = [
            'row_version' => (int) ($row['row_version'] ?? 1),
            'name' => (string) ($row['name'] ?? ''),
            'phone' => $row['phone'] ?? null,
            'address' => $row['address'] ?? null,
            'notes' => $row['notes'] ?? null,
            'partner_number' => $row[$numberColumn] ?? null,
            'credit_limit' => isset($row['credit_limit']) ? (float) $row['credit_limit'] : 0.0,
            'overdue_alert_days' => $row['overdue_alert_days'] !== null
                ? (int) $row['overdue_alert_days']
                : null,
            'deleted_at' => $row['deleted_at'] ?? null,
        ];
        if (array_key_exists($groupColumn, $row)) {
            $shaped[$groupColumn] = $row[$groupColumn];
        }

        return $shaped;
    }

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    private function normalizePartnerPayloadAliases(array $payload): array
    {
        $numberColumn = $this->partnerNumberColumn();
        if (!array_key_exists('partner_number', $payload) && array_key_exists($numberColumn, $payload)) {
            $payload['partner_number'] = $payload[$numberColumn];
        }

        return $payload;
    }

    /**
     * @param array<string, mixed> $row dictionary-shaped
     * @return array<string, mixed>
     */
    private function partnerEnvelopeFromRow(
        string $companyId,
        string $branchId,
        string $entityId,
        array $row,
        bool $deleted,
        bool $noOp,
    ): array {
        $result = [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'name' => (string) ($row['name'] ?? ''),
            'phone' => $row['phone'] ?? null,
            'address' => $row['address'] ?? null,
            'notes' => $row['notes'] ?? null,
            'partner_number' => $row['partner_number'] ?? null,
            'credit_limit' => (float) ($row['credit_limit'] ?? 0),
            'overdue_alert_days' => $row['overdue_alert_days'] !== null
                ? (int) $row['overdue_alert_days']
                : null,
            'row_version' => (int) ($row['row_version'] ?? 1),
            'deleted' => $deleted,
            'no_op' => $noOp,
        ];
        $groupColumn = $this->partnerTable() === 'customers' ? 'customer_group_id' : 'supplier_group_id';
        if (array_key_exists($groupColumn, $row)) {
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
