<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Devices\Validators;

final class RegisterDeviceValidator extends DeviceValidator
{
    public function __construct(private readonly array $payload) {}

    /** @return list<string> */
    protected function errors(): array
    {
        $errors = [];

        foreach ([
            $this->requireString($this->payload, 'installation_id', 'Installation ID'),
            $this->requireString($this->payload, 'device_fingerprint', 'Device fingerprint'),
            $this->requireString($this->payload, 'platform', 'Platform'),
            $this->requireString($this->payload, 'device_name', 'Device name'),
            $this->requireString($this->payload, 'os_name', 'OS name'),
            $this->requireUuid($this->payload, 'company_id', 'Company ID'),
            $this->requireUuid($this->payload, 'branch_id', 'Branch ID'),
        ] as $error) {
            if ($error !== null) {
                $errors[] = $error;
            }
        }

        return $errors;
    }
}
