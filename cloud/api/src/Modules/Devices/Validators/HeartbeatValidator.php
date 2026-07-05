<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Devices\Validators;

final class HeartbeatValidator extends DeviceValidator
{
    public function __construct(private readonly array $payload) {}

    /** @return list<string> */
    protected function errors(): array
    {
        if (isset($this->payload['app_version']) && !is_string($this->payload['app_version'])) {
            return ['app_version:must be a string'];
        }

        return [];
    }
}
