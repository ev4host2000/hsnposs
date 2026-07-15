<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Support;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Modules\Sync\Repositories\SyncRepositorySupport;

/**
 * Shared catalog apply for simple named entities (categories, later units, …).
 * Mirrors Products/Partners: create full insert; update/patch via CatalogPatchOrchestrator;
 * delete version-gated. No full-entity overwrite on update.
 */
trait NamedEntityLww
{
    abstract protected function namedPatchOrchestrator(): CatalogPatchOrchestrator;

    abstract protected function namedEntityType(): string;

    abstract protected function namedEntityPath(): string;

    abstract protected function namedTable(): string;

    /**
     * Dictionary field names that map 1:1 to DB columns (e.g. name, sort_order).
     *
     * @return list<string>
     */
    abstract protected function namedPatchableColumns(): array;

    /**
     * @param array<string, mixed> $payload
     * @param array<string, mixed> $event
     * @return array<string, mixed>
     */
    protected function applyNamedEntityLww(
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
            return $this->applyNamedDelete(
                $companyId,
                $branchId,
                $entityId,
                $clientRowVersion,
                $event,
            );
        }

        if ($operation === 'patch') {
            return $this->applyNamedPatchUpdate(
                $companyId,
                $branchId,
                $entityId,
                $operation,
                $payload,
                $clientRowVersion,
                $event,
            );
        }

        if ($operation !== 'create' && $operation !== 'update') {
            $operation = 'update';
        }

        if ($operation === 'create') {
            return $this->applyNamedCreate(
                $companyId,
                $branchId,
                $entityId,
                $payload,
                $clientRowVersion,
                $event,
            );
        }

        $existing = $this->fetchNamedRow($companyId, $entityId);
        if ($existing === null) {
            return $this->applyNamedCreate(
                $companyId,
                $branchId,
                $entityId,
                $payload,
                $clientRowVersion,
                $event,
            );
        }

        return $this->applyNamedPatchUpdate(
            $companyId,
            $branchId,
            $entityId,
            $operation,
            $payload,
            $clientRowVersion,
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
    private function applyNamedPatchUpdate(
        string $companyId,
        string $branchId,
        string $entityId,
        string $operation,
        array $payload,
        int $clientRowVersion,
        array $event,
        ?array $existing = null,
    ): array {
        $existing ??= $this->fetchNamedRow($companyId, $entityId);
        if ($existing === null) {
            throw new HttpException(
                'version_conflict',
                'Named entity patch rejected: entity not found',
                409,
            );
        }

        try {
            $plan = $this->namedPatchOrchestrator()->planUpdate(
                $this->namedEntityType(),
                $this->namedEntityPath(),
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
                'Named entity update rejected: stale or conflicting base_row_version',
                409,
            );
        }

        if ($plan['decision'] === CatalogVersionGate::DECISION_NO_OP) {
            return $this->namedEnvelopeFromRow(
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
            return $this->namedEnvelopeFromRow(
                $companyId,
                $branchId,
                $entityId,
                $existing,
                deleted: false,
                noOp: true,
            );
        }

        $row = $this->executeNamedPatch(
            $companyId,
            $entityId,
            $fields,
            (int) $plan['new_row_version'],
            (int) ($existing['row_version'] ?? 1),
        );

        return $this->namedEnvelopeFromRow(
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
    private function executeNamedPatch(
        string $companyId,
        string $entityId,
        array $fields,
        int $newRowVersion,
        int $expectedServerVersion,
    ): array {
        $table = $this->namedTable();
        $allowed = $this->namedPatchableColumns();

        $setParts = [];
        $params = [
            'id' => $entityId,
            'company_id' => $companyId,
            'new_row_version' => $newRowVersion,
            'expected_version' => $expectedServerVersion,
        ];

        foreach ($fields as $name => $value) {
            if (!in_array($name, $allowed, true)) {
                throw new HttpException(
                    'validation_error',
                    'Forbidden or unknown patch column: ' . $name,
                    400,
                );
            }
            $param = 'f_' . preg_replace('/[^a-z0-9_]/', '_', $name);
            $setParts[] = "{$name} = :{$param}";
            $params[$param] = $this->bindNamedColumnValue($name, $value);
        }

        if ($setParts === []) {
            $existing = $this->fetchNamedRow($companyId, $entityId);
            if ($existing === null) {
                throw new HttpException('version_conflict', 'Named entity patch rejected: entity not found', 409);
            }

            return $existing;
        }

        $setParts[] = 'row_version = :new_row_version';
        $setParts[] = 'updated_at = now()';
        $setParts[] = 'deleted_at = NULL';

        $returnColumns = 'row_version, deleted_at, ' . implode(', ', $allowed);

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
                'Named entity update rejected: concurrent version change',
                409,
            );
        }

        return $this->dictionaryShapeFromNamedDbRow($row);
    }

    /**
     * @param array<string, mixed> $payload
     * @param array<string, mixed> $event
     * @return array<string, mixed>
     */
    private function applyNamedCreate(
        string $companyId,
        string $branchId,
        string $entityId,
        array $payload,
        int $clientRowVersion,
        array $event,
    ): array {
        $existing = $this->fetchNamedRow($companyId, $entityId);
        if ($existing !== null) {
            return $this->applyNamedPatchUpdate(
                $companyId,
                $branchId,
                $entityId,
                'update',
                $payload,
                $clientRowVersion,
                $event === []
                    ? ['operation_id' => (string) ($payload['operation_id'] ?? $entityId . ':create')]
                    : $event,
                $existing,
            );
        }

        $decision = CatalogVersionGate::decide(
            CatalogVersionGate::OPERATION_CREATE,
            null,
            max(1, $clientRowVersion),
            false,
        );

        if ($decision === CatalogVersionGate::DECISION_CONFLICT) {
            throw new HttpException(
                'version_conflict',
                'Named entity create rejected: stale or conflicting row_version',
                409,
            );
        }

        $table = $this->namedTable();
        $allowed = $this->namedPatchableColumns();
        $rowVersion = max(1, $clientRowVersion);

        $columns = ['id', 'company_id', 'branch_id'];
        $values = [':id', ':company_id', ':branch_id'];
        $params = [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'row_version' => $rowVersion,
        ];

        foreach ($allowed as $column) {
            $columns[] = $column;
            $param = 'c_' . preg_replace('/[^a-z0-9_]/', '_', $column);
            $values[] = ':' . $param;
            $params[$param] = $this->bindNamedColumnValue(
                $column,
                $this->defaultNamedColumnFromPayload($column, $payload),
            );
        }

        $columns = array_merge($columns, ['row_version', 'created_at', 'updated_at', 'deleted_at']);
        $values = array_merge($values, [':row_version', 'now()', 'now()', 'NULL']);

        $returnColumns = 'row_version, deleted_at, ' . implode(', ', $allowed);

        $sql = 'INSERT INTO ' . $table . ' (' . implode(', ', $columns) . ')
             VALUES (' . implode(', ', $values) . ')
             RETURNING ' . $returnColumns;

        $stmt = $this->db->pdo()->prepare($sql);
        $stmt->execute($params);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new HttpException('internal_error', 'Named entity create failed', 500);
        }

        return $this->namedEnvelopeFromRow(
            $companyId,
            $branchId,
            $entityId,
            $this->dictionaryShapeFromNamedDbRow($row),
            deleted: false,
            noOp: false,
        );
    }

    /**
     * @param array<string, mixed> $event
     * @return array<string, mixed>
     */
    private function applyNamedDelete(
        string $companyId,
        string $branchId,
        string $entityId,
        int $clientRowVersion,
        array $event = [],
    ): array {
        $existing = $this->fetchNamedRow($companyId, $entityId);
        $serverRowVersion = $existing === null ? null : (int) ($existing['row_version'] ?? 1);
        $alreadyDeleted = $existing !== null && ($existing['deleted_at'] ?? null) !== null;

        $versionForGate = $clientRowVersion;
        if (isset($event['base_row_version']) && is_numeric($event['base_row_version'])) {
            $base = (int) $event['base_row_version'];
            if ($base >= 1 && $serverRowVersion !== null && $base !== $serverRowVersion) {
                throw new HttpException(
                    'version_conflict',
                    'Named entity delete rejected: stale or conflicting base_row_version',
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
                'Named entity delete rejected: stale or conflicting row_version',
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

            return $this->namedEnvelopeFromRow(
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
            $this->namedTable(),
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
     * @return array<string, mixed>|null
     */
    private function fetchNamedRow(string $companyId, string $entityId): ?array
    {
        $table = $this->namedTable();
        $allowed = $this->namedPatchableColumns();
        $cols = 'id, company_id, branch_id, row_version, deleted_at, ' . implode(', ', $allowed);

        $stmt = $this->db->pdo()->prepare(
            'SELECT ' . $cols . ' FROM ' . $table
            . ' WHERE id = :id AND company_id = :company_id LIMIT 1',
        );
        $stmt->execute(['id' => $entityId, 'company_id' => $companyId]);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC);

        return is_array($row) ? $this->dictionaryShapeFromNamedDbRow($row) : null;
    }

    /**
     * @param array<string, mixed> $row
     * @return array<string, mixed>
     */
    private function dictionaryShapeFromNamedDbRow(array $row): array
    {
        $shaped = [
            'row_version' => (int) ($row['row_version'] ?? 1),
            'deleted_at' => $row['deleted_at'] ?? null,
        ];
        foreach ($this->namedPatchableColumns() as $name) {
            if (!array_key_exists($name, $row)) {
                continue;
            }
            $shaped[$name] = $this->shapeNamedColumnValue($name, $row[$name]);
        }

        return $shaped;
    }

    /**
     * @param array<string, mixed> $payload
     */
    private function defaultNamedColumnFromPayload(string $column, array $payload): mixed
    {
        if ($column === 'name') {
            return trim((string) ($payload['name'] ?? ''));
        }
        if (!array_key_exists($column, $payload)) {
            return match ($column) {
                'sort_order' => 0,
                'percent' => 0.0,
                'is_default' => false,
                default => null,
            };
        }

        return $payload[$column];
    }

    private function bindNamedColumnValue(string $column, mixed $value): mixed
    {
        if ($column === 'name') {
            return trim((string) $value);
        }
        if ($column === 'sort_order') {
            return (int) $value;
        }
        if ($column === 'percent') {
            return (float) $value;
        }
        if ($column === 'is_default' || str_starts_with($column, 'is_')) {
            return $this->normalizeNamedBool($value) ? 't' : 'f';
        }

        return $value;
    }

    private function shapeNamedColumnValue(string $column, mixed $value): mixed
    {
        if ($column === 'name') {
            return (string) $value;
        }
        if ($column === 'sort_order') {
            return (int) $value;
        }
        if ($column === 'percent') {
            return (float) $value;
        }
        if ($column === 'is_default' || str_starts_with($column, 'is_')) {
            return $this->normalizeNamedBool($value);
        }

        return $value;
    }

    private function normalizeNamedBool(mixed $value): bool
    {
        if (is_bool($value)) {
            return $value;
        }
        if (is_int($value)) {
            return $value !== 0;
        }
        $raw = strtolower(trim((string) $value));

        return in_array($raw, ['1', 't', 'true', 'yes', 'y', 'on'], true);
    }

    /**
     * @param array<string, mixed> $row
     * @return array<string, mixed>
     */
    private function namedEnvelopeFromRow(
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
            'row_version' => (int) ($row['row_version'] ?? 1),
            'deleted' => $deleted,
            'no_op' => $noOp,
        ];
        foreach ($this->namedPatchableColumns() as $name) {
            if (array_key_exists($name, $row)) {
                $result[$name] = $row[$name];
            }
        }

        return $result;
    }
}
