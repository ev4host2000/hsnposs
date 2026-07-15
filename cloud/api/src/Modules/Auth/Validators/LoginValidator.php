<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Auth\Validators;

final class LoginValidator extends AuthValidator
{
    public function __construct(private readonly array $payload) {}

    /** @return list<string> */
    protected function errors(): array
    {
        $errors = [];

        foreach ([
            $this->requireString($this->payload, 'username', 'Username'),
            $this->requireString($this->payload, 'password', 'Password'),
            $this->requireString($this->payload, 'installation_id', 'Installation ID'),
        ] as $error) {
            if ($error !== null) {
                $errors[] = $error;
            }
        }

        $companyId = $this->payload['company_id'] ?? null;
        if ($companyId !== null && $companyId !== '' && !\MizaCloud\Modules\Auth\Support\Uuid::isValid((string) $companyId)) {
            $errors[] = 'company_id:Company ID must be a valid UUID';
        }

        $branchId = $this->payload['branch_id'] ?? null;
        if ($branchId !== null && $branchId !== '' && !\MizaCloud\Modules\Auth\Support\Uuid::isValid((string) $branchId)) {
            $errors[] = 'branch_id:Branch ID must be a valid UUID';
        }

        $deviceId = $this->payload['device_id'] ?? null;
        if ($deviceId !== null && $deviceId !== '' && !\MizaCloud\Modules\Auth\Support\Uuid::isValid((string) $deviceId)) {
            $errors[] = 'device_id:Device ID must be a valid UUID';
        }

        return $errors;
    }
}
