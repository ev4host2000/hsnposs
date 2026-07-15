<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Admin\Services;

use MizaCloud\Core\Config\Config;
use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;
use MizaCloud\Modules\Admin\Repositories\OpsAuditRepository;
use MizaCloud\Modules\Admin\Support\OpsAuditActions;
use MizaCloud\Modules\Admin\Support\OpsAuditContext;
use MizaCloud\Modules\Admin\Support\PlatformAdminBearer;
use MizaCloud\Modules\Auth\Support\Uuid;

/**
 * Admin-facing Audit Log APIs (read / export / retention / alerts).
 * Does not mutate audit rows.
 */
final class OpsAuditService
{
    public function __construct(
        private readonly OpsAuditRepository $repository,
        private readonly PlatformAdminBearer $bearer,
        private readonly Config $config,
        private readonly OpsAuditWriter $writer,
    ) {}

    public function listEvents(Request $request): array
    {
        $this->bearer->authenticate($request, ['platform:read']);
        $filters = $this->filtersFromRequest($request);
        $limit = max(1, min((int) ($request->query['limit'] ?? 50), 200));
        $offset = max(0, (int) ($request->query['offset'] ?? 0));
        $sortBy = (string) ($request->query['sort_by'] ?? 'created_at');
        $sortDir = (string) ($request->query['sort_dir'] ?? 'desc');

        return [
            'total' => $this->repository->count($filters),
            'limit' => $limit,
            'offset' => $offset,
            'sort_by' => $sortBy,
            'sort_dir' => $sortDir,
            'entries' => $this->repository->search($filters, $limit, $offset, $sortBy, $sortDir),
            'actions_catalog' => OpsAuditActions::all(),
        ];
    }

    public function getEvent(Request $request, string $id): array
    {
        $this->bearer->authenticate($request, ['platform:read']);
        if (!Uuid::isValid($id)) {
            throw new HttpException('validation_error', 'Invalid audit id', 400);
        }
        $row = $this->repository->findById($id);
        if ($row === null) {
            throw new HttpException('not_found', 'Audit event not found', 404);
        }

        return ['event' => $row];
    }

    public function alerts(Request $request): array
    {
        $this->bearer->authenticate($request, ['platform:read']);
        $cfg = $this->auditConfig();

        return [
            'alerts' => $this->repository->securityAlerts(
                is_array($cfg['alert_thresholds'] ?? null) ? $cfg['alert_thresholds'] : [],
                (int) ($cfg['alert_window_minutes'] ?? 60),
            ),
            'thresholds' => $cfg['alert_thresholds'] ?? [],
            'window_minutes' => (int) ($cfg['alert_window_minutes'] ?? 60),
        ];
    }

    public function getRetention(Request $request): array
    {
        $this->bearer->authenticate($request, ['platform:read']);
        $db = $this->repository->getRetention();
        $cfg = $this->auditConfig();

        return [
            'days' => (int) ($db['days'] ?? ($cfg['retention_days'] ?? 90)),
            'archive_enabled' => (bool) ($db['archive_enabled'] ?? ($cfg['archive_enabled'] ?? true)),
            'allowed_days' => [90, 180, 365],
        ];
    }

    public function updateRetention(Request $request, array $payload): array
    {
        $this->bearer->authenticate($request, ['platform:write']);
        $days = (int) ($payload['days'] ?? 90);
        $archive = array_key_exists('archive_enabled', $payload)
            ? (bool) $payload['archive_enabled']
            : true;
        $before = $this->repository->getRetention();
        $after = $this->repository->setRetention($days, $archive);
        $this->writer->write(array_merge(OpsAuditContext::fromRequest($request), [
            'action' => OpsAuditActions::SETTINGS_CHANGED,
            'status' => 'success',
            'entity' => 'ops_audit_settings',
            'entity_id' => 'retention',
            'user_name' => 'platform_admin',
            'role' => 'platform_admin',
            'metadata' => ['before' => $before, 'after' => $after],
        ]));

        return $after;
    }

    public function runRetention(Request $request): array
    {
        $this->bearer->authenticate($request, ['platform:write']);
        $result = $this->repository->runRetentionArchive();
        $this->writer->write(array_merge(OpsAuditContext::fromRequest($request), [
            'action' => OpsAuditActions::BACKUP_FINISHED,
            'status' => 'success',
            'entity' => 'ops_audit_events',
            'user_name' => 'platform_admin',
            'role' => 'platform_admin',
            'reason' => 'retention_archive',
            'metadata' => $result,
        ]));

        return $result;
    }

    /** Blocked mutation — logs attempt and rejects. */
    public function rejectMutation(Request $request, string $attempt): array
    {
        try {
            $this->bearer->authenticate($request, ['platform:read']);
        } catch (HttpException) {
            // still log attempt when possible
        }
        $this->writer->write(array_merge(OpsAuditContext::fromRequest($request), [
            'action' => OpsAuditActions::AUDIT_MUTATION_BLOCKED,
            'status' => 'failure',
            'severity' => 'critical',
            'entity' => 'ops_audit_events',
            'reason' => $attempt,
            'error_code' => 'audit_immutable',
            'error_message' => 'Audit events are immutable',
            'user_name' => 'platform_admin',
            'role' => 'platform_admin',
        ]));
        throw new HttpException('forbidden', 'Audit events are immutable and cannot be modified or deleted', 403);
    }

    public function export(Request $request): Response
    {
        $this->bearer->authenticate($request, ['platform:read']);
        $filters = $this->filtersFromRequest($request);
        $format = strtolower(trim((string) ($request->query['format'] ?? 'csv')));
        $cfg = $this->auditConfig();
        $max = (int) ($cfg['export_max_rows'] ?? 5000);
        $rows = $this->repository->exportRows($filters, $max);
        $stamp = gmdate('Ymd_His');

        return match ($format) {
            'json' => new Response(
                200,
                json_encode(['ok' => true, 'data' => ['entries' => $rows, 'count' => count($rows)]], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) ?: '{}',
                [
                    'Content-Type' => 'application/json; charset=utf-8',
                    'Content-Disposition' => "attachment; filename=\"miza_audit_{$stamp}.json\"",
                ],
            ),
            'xlsx', 'excel' => new Response(
                200,
                $this->toSpreadsheetMl($rows),
                [
                    'Content-Type' => 'application/vnd.ms-excel; charset=utf-8',
                    'Content-Disposition' => "attachment; filename=\"miza_audit_{$stamp}.xls\"",
                ],
            ),
            'pdf' => new Response(
                200,
                $this->toSimplePdf($rows),
                [
                    'Content-Type' => 'application/pdf',
                    'Content-Disposition' => "attachment; filename=\"miza_audit_{$stamp}.pdf\"",
                ],
            ),
            default => new Response(
                200,
                $this->toCsv($rows),
                [
                    'Content-Type' => 'text/csv; charset=utf-8',
                    'Content-Disposition' => "attachment; filename=\"miza_audit_{$stamp}.csv\"",
                ],
            ),
        };
    }

    /** @return array<string, mixed> */
    private function filtersFromRequest(Request $request): array
    {
        $q = $request->query;

        return [
            'q' => trim((string) ($q['q'] ?? $q['search'] ?? '')),
            'organization_id' => trim((string) ($q['organization_id'] ?? $q['company_id'] ?? '')),
            'branch_id' => trim((string) ($q['branch_id'] ?? '')),
            'user_id' => trim((string) ($q['user_id'] ?? '')),
            'device_id' => trim((string) ($q['device_id'] ?? '')),
            'entity' => trim((string) ($q['entity'] ?? '')),
            'action' => trim((string) ($q['action'] ?? '')),
            'status' => trim((string) ($q['status'] ?? '')),
            'severity' => trim((string) ($q['severity'] ?? '')),
            'error_code' => trim((string) ($q['error_code'] ?? '')),
            'date_from' => trim((string) ($q['date_from'] ?? '')),
            'date_to' => trim((string) ($q['date_to'] ?? '')),
        ];
    }

    /** @return array<string, mixed> */
    private function auditConfig(): array
    {
        $cfg = $this->config->get('audit', []);

        return is_array($cfg) ? $cfg : [];
    }

    /** @param list<array<string, mixed>> $rows */
    private function toCsv(array $rows): string
    {
        $out = fopen('php://temp', 'r+');
        if ($out === false) {
            return '';
        }
        fprintf($out, chr(0xEF) . chr(0xBB) . chr(0xBF));
        $headers = [
            'id', 'timestamp_utc', 'organization_id', 'branch_id', 'user_id', 'user_name', 'role',
            'device_id', 'entity', 'entity_id', 'action', 'status', 'severity', 'reason',
            'ip_address', 'error_code', 'error_message', 'duration', 'correlation_id',
        ];
        fputcsv($out, $headers);
        foreach ($rows as $row) {
            $line = [];
            foreach ($headers as $h) {
                $line[] = (string) ($row[$h] ?? '');
            }
            fputcsv($out, $line);
        }
        rewind($out);
        $csv = stream_get_contents($out) ?: '';
        fclose($out);

        return $csv;
    }

    /** @param list<array<string, mixed>> $rows */
    private function toSpreadsheetMl(array $rows): string
    {
        $xml = '<?xml version="1.0" encoding="UTF-8"?>'
            . '<?mso-application progid="Excel.Sheet"?>'
            . '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"'
            . ' xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">'
            . '<Worksheet ss:Name="Audit"><Table>';
        $headers = ['id', 'timestamp_utc', 'organization_id', 'action', 'status', 'severity', 'entity', 'user_name', 'ip_address', 'error_code', 'reason'];
        $xml .= '<Row>';
        foreach ($headers as $h) {
            $xml .= '<Cell><Data ss:Type="String">' . htmlspecialchars($h, ENT_XML1) . '</Data></Cell>';
        }
        $xml .= '</Row>';
        foreach ($rows as $row) {
            $xml .= '<Row>';
            foreach ($headers as $h) {
                $xml .= '<Cell><Data ss:Type="String">' . htmlspecialchars((string) ($row[$h] ?? ''), ENT_XML1) . '</Data></Cell>';
            }
            $xml .= '</Row>';
        }
        $xml .= '</Table></Worksheet></Workbook>';

        return $xml;
    }

    /** @param list<array<string, mixed>> $rows */
    private function toSimplePdf(array $rows): string
    {
        $lines = ['Miza Cloud Audit Log', 'Generated: ' . gmdate('c') . ' UTC', str_repeat('-', 72)];
        foreach (array_slice($rows, 0, 200) as $row) {
            $lines[] = sprintf(
                '%s | %s | %s | %s | %s',
                (string) ($row['timestamp_utc'] ?? ''),
                (string) ($row['action'] ?? ''),
                (string) ($row['status'] ?? ''),
                (string) ($row['organization_id'] ?? '-'),
                (string) ($row['reason'] ?? ($row['error_code'] ?? '')),
            );
        }
        $content = implode("\n", $lines);
        $escaped = str_replace(['\\', '(', ')'], ['\\\\', '\\(', '\\)'], $content);
        $stream = "BT /F1 9 Tf 40 800 Td 12 TL (" . str_replace("\n", ") Tj T* (", $escaped) . ") Tj ET";
        $objects = [];
        $objects[] = "1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n";
        $objects[] = "2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n";
        $objects[] = "3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>endobj\n";
        $objects[] = '4 0 obj<< /Length ' . strlen($stream) . " >>stream\n{$stream}\nendstream\nendobj\n";
        $objects[] = "5 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>endobj\n";

        $pdf = "%PDF-1.4\n";
        $offsets = [0];
        foreach ($objects as $obj) {
            $offsets[] = strlen($pdf);
            $pdf .= $obj;
        }
        $xref = strlen($pdf);
        $pdf .= 'xref
0 ' . (count($objects) + 1) . "
0000000000 65535 f 
";
        for ($i = 1; $i <= count($objects); $i++) {
            $pdf .= sprintf("%010d 00000 n \n", $offsets[$i]);
        }
        $pdf .= 'trailer<< /Size ' . (count($objects) + 1) . " /Root 1 0 R >>\nstartxref\n{$xref}\n%%EOF";

        return $pdf;
    }
}
