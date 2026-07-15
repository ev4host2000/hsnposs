<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Health\Services;

use DateTimeImmutable;
use DateTimeZone;
use MizaCloud\Core\Config\Config;
use MizaCloud\Core\Http\Request;
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

    /**
     * RAP-P1-06: public version omits environment/php_version unless detail authorized.
     *
     * @return array<string, mixed>
     */
    public function version(bool $detailed = false): array
    {
        $app = $this->config->get('app', []);
        $payload = [
            'name' => (string) ($app['name'] ?? 'Miza Cloud API'),
            'api_version' => (string) ($app['api_version'] ?? 'v1'),
        ];

        if ($detailed) {
            $payload['environment'] = (string) ($app['env'] ?? 'production');
            $payload['php_version'] = PHP_VERSION;
        }

        return $payload;
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
     * RAP-P1-06: public database status is connected flag only.
     *
     * @return array<string, mixed>
     */
    public function database(bool $detailed = false): array
    {
        $status = $this->repository->databaseStatus();
        $level = $status['connected'] ? 'info' : 'warning';
        $this->logger->log($level, 'health.database', [
            'connected' => $status['connected'],
            'detailed' => $detailed,
        ]);

        if ($detailed) {
            return $status;
        }

        return [
            'connected' => $status['connected'],
        ];
    }

    /**
     * @return array<string, mixed>
     */
    public function summary(bool $detailed = false): array
    {
        $database = $this->repository->databaseStatus();
        $loggerOk = $this->probeLogger();
        $allUp = $database['connected'] && $loggerOk;

        $this->logger->info('health.summary', [
            'status' => $allUp ? 'healthy' : 'degraded',
            'database_connected' => $database['connected'],
            'detailed' => $detailed,
        ]);

        $databaseCheck = [
            'status' => $database['connected'] ? 'up' : 'down',
        ];
        if ($detailed) {
            $databaseCheck['latency_ms'] = $database['latency_ms'];
        }

        return [
            'status' => $allUp ? 'healthy' : 'degraded',
            'timestamp' => gmdate('Y-m-d\TH:i:s.v\Z'),
            'checks' => [
                'application' => ['status' => 'up'],
                'router' => ['status' => 'up'],
                'response_builder' => ['status' => 'up'],
                'logger' => ['status' => $loggerOk ? 'up' : 'down'],
                'database' => $databaseCheck,
            ],
            'version' => $this->version($detailed),
        ];
    }

    /** RAP-P1-06: detail views require matching X-Health-Token when token is configured. */
    public function isDetailAuthorized(Request $request): bool
    {
        $app = $this->config->get('app', []);
        $expected = trim((string) ($app['health_detail_token'] ?? ''));
        if ($expected === '') {
            return false;
        }

        $provided = $this->headerValue($request, 'X-Health-Token');
        if ($provided === null || $provided === '') {
            return false;
        }

        return hash_equals($expected, $provided);
    }

    private function headerValue(Request $request, string $name): ?string
    {
        foreach ($request->headers as $key => $value) {
            if (strcasecmp((string) $key, $name) === 0) {
                return is_string($value) ? trim($value) : null;
            }
        }

        return null;
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
