<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Support;

/**
 * Strict Optimistic Concurrency with Safe Equality — pure decision logic.
 *
 * No database, HTTP, or repository dependencies.
 *
 * Rules:
 * - client < server  → Conflict
 * - client > server  → Apply
 * - client == server → NoOp if payload matches server state; otherwise Conflict
 *
 * Create (no server row): always Apply.
 * Delete at equal version: Apply when the row is still active; NoOp when already deleted
 * (payloadMatchesServerState === true means tombstone already matches delete intent).
 */
final class CatalogVersionGate
{
    public const DECISION_APPLY = 'apply';
    public const DECISION_NO_OP = 'no_op';
    public const DECISION_CONFLICT = 'version_conflict';

    public const OPERATION_CREATE = 'create';
    public const OPERATION_UPDATE = 'update';
    public const OPERATION_DELETE = 'delete';

    /**
     * @param self::OPERATION_* $operation
     * @param ?int $serverRowVersion null when the entity row does not exist on the server
     * @param int $clientRowVersion version supplied by the client event
     * @param bool $payloadMatchesServerState
     *        Update: payload fields equal current server field state.
     *        Delete: server row is already deleted (delete is idempotent).
     *        Create: ignored.
     * @return self::DECISION_*
     */
    public static function decide(
        string $operation,
        ?int $serverRowVersion,
        int $clientRowVersion,
        bool $payloadMatchesServerState = false,
    ): string {
        $operation = strtolower(trim($operation));
        if (!in_array($operation, [
            self::OPERATION_CREATE,
            self::OPERATION_UPDATE,
            self::OPERATION_DELETE,
        ], true)) {
            throw new \InvalidArgumentException('Unsupported catalog version operation: ' . $operation);
        }

        if ($clientRowVersion < 1) {
            throw new \InvalidArgumentException('client_row_version must be >= 1');
        }

        if ($serverRowVersion !== null && $serverRowVersion < 1) {
            throw new \InvalidArgumentException('server_row_version must be >= 1 when present');
        }

        return match ($operation) {
            self::OPERATION_CREATE => self::decideCreate($serverRowVersion, $clientRowVersion, $payloadMatchesServerState),
            self::OPERATION_UPDATE => self::decideUpdate($serverRowVersion, $clientRowVersion, $payloadMatchesServerState),
            self::OPERATION_DELETE => self::decideDelete($serverRowVersion, $clientRowVersion, $payloadMatchesServerState),
        };
    }

    /**
     * @return self::DECISION_*
     */
    private static function decideCreate(
        ?int $serverRowVersion,
        int $clientRowVersion,
        bool $payloadMatchesServerState,
    ): string {
        // Brand-new entity: no server row → apply insert.
        if ($serverRowVersion === null) {
            return self::DECISION_APPLY;
        }

        // Create against an existing row is evaluated with update/safe-equality rules.
        return self::compareExisting($serverRowVersion, $clientRowVersion, $payloadMatchesServerState);
    }

    /**
     * @return self::DECISION_*
     */
    private static function decideUpdate(
        ?int $serverRowVersion,
        int $clientRowVersion,
        bool $payloadMatchesServerState,
    ): string {
        // Missing row on update path → treat as insert apply (caller may upsert).
        if ($serverRowVersion === null) {
            return self::DECISION_APPLY;
        }

        return self::compareExisting($serverRowVersion, $clientRowVersion, $payloadMatchesServerState);
    }

    /**
     * @return self::DECISION_*
     */
    private static function decideDelete(
        ?int $serverRowVersion,
        int $clientRowVersion,
        bool $payloadMatchesServerState,
    ): string {
        // Nothing to delete.
        if ($serverRowVersion === null) {
            return self::DECISION_NO_OP;
        }

        if ($clientRowVersion < $serverRowVersion) {
            return self::DECISION_CONFLICT;
        }

        if ($clientRowVersion > $serverRowVersion) {
            return self::DECISION_APPLY;
        }

        // client == server
        // Already deleted (matches delete intent) → safe no-op.
        if ($payloadMatchesServerState) {
            return self::DECISION_NO_OP;
        }

        // Active row at current version → authorized delete.
        return self::DECISION_APPLY;
    }

    /**
     * Shared compare for an existing server row (update / create-on-existing).
     *
     * @return self::DECISION_*
     */
    private static function compareExisting(
        int $serverRowVersion,
        int $clientRowVersion,
        bool $payloadMatchesServerState,
    ): string {
        if ($clientRowVersion < $serverRowVersion) {
            return self::DECISION_CONFLICT;
        }

        if ($clientRowVersion > $serverRowVersion) {
            return self::DECISION_APPLY;
        }

        // client == server — Safe Equality
        if ($payloadMatchesServerState) {
            return self::DECISION_NO_OP;
        }

        return self::DECISION_CONFLICT;
    }

    /**
     * Update Contract v2 patch gate: base_row_version must equal server.row_version.
     *
     * - base != server → version_conflict
     * - base == server && effective no-op → no_op
     * - base == server && has effective changes → apply
     *
     * @return self::DECISION_*
     */
    public static function decidePatch(
        ?int $serverRowVersion,
        int $baseRowVersion,
        bool $changesAreNoOp,
    ): string {
        if ($baseRowVersion < 1) {
            throw new \InvalidArgumentException('base_row_version must be >= 1');
        }
        if ($serverRowVersion !== null && $serverRowVersion < 1) {
            throw new \InvalidArgumentException('server_row_version must be >= 1 when present');
        }

        // Patch requires an existing authoritative row.
        if ($serverRowVersion === null) {
            return self::DECISION_CONFLICT;
        }

        if ($baseRowVersion !== $serverRowVersion) {
            return self::DECISION_CONFLICT;
        }

        if ($changesAreNoOp) {
            return self::DECISION_NO_OP;
        }

        return self::DECISION_APPLY;
    }
}
