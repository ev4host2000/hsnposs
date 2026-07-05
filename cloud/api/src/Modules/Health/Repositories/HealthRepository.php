<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Health\Repositories;

use MizaCloud\Core\Database\DatabaseManager;
use Throwable;

/**
 * فحص اتصال PostgreSQL فقط — بدون جداول أعمال.
 */
final class HealthRepository
{
    public function __construct(private readonly DatabaseManager $database) {}

    /**
     * @return array{connected: bool, latency_ms: float|null, server_time: string|null, error: string|null}
     */
    public function databaseStatus(): array
    {
        $started = microtime(true);

        try {
            $pdo = $this->database->connection()->pdo();
            $pdo->query('SELECT 1');
            $row = $pdo->query('SELECT now() AT TIME ZONE \'UTC\' AS server_time')->fetch();
            $latencyMs = round((microtime(true) - $started) * 1000, 2);

            return [
                'connected' => true,
                'latency_ms' => $latencyMs,
                'server_time' => is_array($row) ? (string) ($row['server_time'] ?? '') : null,
                'error' => null,
            ];
        } catch (Throwable $e) {
            return [
                'connected' => false,
                'latency_ms' => null,
                'server_time' => null,
                'error' => $e->getMessage(),
            ];
        }
    }
}
