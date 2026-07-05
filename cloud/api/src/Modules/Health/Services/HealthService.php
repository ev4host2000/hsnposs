<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Health\Services;

use DateTimeImmutable;
use DateTimeZone;
use MizaCloud\Core\Config\Config;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Modules\Health\Repositories\HealthRepository;

final class HealthService
{
    public function __construct(
        private readonly HealthRepository $repository,
        private readonly Config $config,
        private readonly Logger $logger,
    ) {}

    public function ping(): array
    {
        $this->logger->debug('health.ping');

        return ['pong' => true];
    }

    public function version(): array
    {
        $app = $this->config->get('app', []);

        return [
            'name' => (string) ($app['name'] ?? 'Miza Cloud API'),
            'api_version' => (string) ($app['api_version'] ?? 'v1'),
            'environment' => (string) ($app['env'] ?? 'production'),
            'php_version' => PHP_VERSION,
        ];
    }

    public function time(): array
    {
        $app = $this->config->get('app', []);
        $timezone = (string) ($app['timezone'] ?? 'UTC');
        $now = new DateTimeImmutable('now', new DateTimeZone($timezone));

        return [
            'utc' => $now->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d\TH:i:s.v\Z'),
            'timezone' => $timezone,
            'local' => $now->format('Y-m-d\TH:i:s.vP'),
            'unix' => $now->getTimestamp(),
        ];
    }

    /**
     * @return array{connected: bool, latency_ms: float|null, server_time: string|null, error: string|null}
     */
    public function database(): array
    {
        $status = $this->repository->databaseStatus();
        $level = $status['connected'] ? 'info' : 'warning';
        $this->logger->log($level, 'health.database', $status);

        return $status;
    }

    public function summary(): array
    {
        $database = $this->repository->databaseStatus();
        $loggerOk = $this->probeLogger();
        $allUp = $database['connected'] && $loggerOk;

        $this->logger->info('health.summary', [
            'status' => $allUp ? 'healthy' : 'degraded',
            'database_connected' => $database['connected'],
        ]);

        return [
            'status' => $allUp ? 'healthy' : 'degraded',
            'timestamp' => gmdate('Y-m-d\TH:i:s.v\Z'),
            'checks' => [
                'application' => ['status' => 'up'],
                'router' => ['status' => 'up'],
                'response_builder' => ['status' => 'up'],
                'logger' => ['status' => $loggerOk ? 'up' : 'down'],
                'database' => [
                    'status' => $database['connected'] ? 'up' : 'down',
                    'latency_ms' => $database['latency_ms'],
                ],
            ],
            'version' => $this->version(),
        ];
    }

    private function probeLogger(): bool
    {
        try {
            $this->logger->debug('health.logger_probe');
            return true;
        } catch (\Throwable) {
            return false;
        }
    }
}
