<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Admin\Services;

use MizaCloud\Core\Config\Config;
use MizaCloud\Core\Http\Request;
use MizaCloud\Modules\Admin\Repositories\OpsAuditRepository;
use MizaCloud\Modules\Admin\Support\OpsAuditActions;
use MizaCloud\Modules\Admin\Support\OpsAuditContext;
use Throwable;

/**
 * Fire-and-forget audit writer. Never throws to callers.
 * When async=true, events are flushed via register_shutdown_function.
 */
final class OpsAuditWriter
{
    private static ?self $instance = null;

    /** @var list<array<string, mixed>> */
    private array $queue = [];

    private bool $shutdownRegistered = false;

    public function __construct(
        private readonly OpsAuditRepository $repository,
        private readonly Config $config,
    ) {}

    public static function setInstance(self $writer): void
    {
        self::$instance = $writer;
    }

    public static function instance(): ?self
    {
        return self::$instance;
    }

    /**
     * @param array<string, mixed> $event
     */
    public static function record(array $event): void
    {
        self::$instance?->write($event);
    }

    /**
     * @param array<string, mixed> $extra
     */
    public static function recordAction(
        string $action,
        string $status = 'success',
        array $extra = [],
        ?Request $request = null,
    ): void {
        $payload = $extra;
        if ($request !== null) {
            $payload = array_merge(OpsAuditContext::fromRequest($request), $payload);
        }
        $payload['action'] = $action;
        $payload['status'] = $status;
        $payload['severity'] = $payload['severity']
            ?? OpsAuditActions::severityFor($action, $status);
        self::record($payload);
    }

    /**
     * @param array<string, mixed> $event
     */
    public function write(array $event): void
    {
        $cfg = $this->config->get('audit', []);
        if (!is_array($cfg)) {
            $cfg = [];
        }
        if (!(bool) ($cfg['enabled'] ?? true)) {
            return;
        }

        $event['action'] = (string) ($event['action'] ?? 'unknown');
        $event['status'] = (string) ($event['status'] ?? 'success');
        $event['severity'] = (string) ($event['severity']
            ?? OpsAuditActions::severityFor($event['action'], $event['status']));

        $async = (bool) ($cfg['async'] ?? true);
        if ($async) {
            $this->queue[] = $event;
            $this->ensureShutdownFlush();

            return;
        }

        $this->persistOne($event);
    }

    public function flush(): void
    {
        if ($this->queue === []) {
            return;
        }
        $batch = $this->queue;
        $this->queue = [];
        foreach ($batch as $event) {
            $this->persistOne($event);
        }
    }

    /** @param array<string, mixed> $event */
    private function persistOne(array $event): void
    {
        try {
            $this->repository->insert($event);
        } catch (Throwable) {
            // Audit must never break business flow.
        }
    }

    private function ensureShutdownFlush(): void
    {
        if ($this->shutdownRegistered) {
            return;
        }
        $this->shutdownRegistered = true;
        register_shutdown_function(function (): void {
            $this->flush();
        });
    }
}
