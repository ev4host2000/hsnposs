<?php

/**
 * How to record a new Ops Audit Event (additive helper usage).
 *
 * Prefer action constants from OpsAuditActions.
 *
 * Example:
 *
 * use MizaCloud\Modules\Admin\Services\OpsAuditWriter;
 * use MizaCloud\Modules\Admin\Support\OpsAuditActions;
 *
 * OpsAuditWriter::recordAction(
 *     OpsAuditActions::SETTINGS_CHANGED,
 *     'success',
 *     [
 *         'organization_id' => $companyId,
 *         'user_id' => $userId,
 *         'user_name' => $userName,
 *         'entity' => 'settings',
 *         'entity_id' => $settingKey,
 *         'reason' => 'theme_updated',
 *         'metadata' => ['before' => $before, 'after' => $after],
 *     ],
 *     $request, // optional Request for IP / UA / request_id
 * );
 *
 * Rules:
 * - Never throw from audit paths (OpsAuditWriter swallows DB errors).
 * - Do not UPDATE or DELETE ops_audit_events rows (DB trigger blocks UPDATE).
 * - Use retention/archive endpoint for aging data.
 */

declare(strict_types=1);
