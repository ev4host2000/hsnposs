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
            $this->requireUuid($this->payload, 'company_id', 'Company ID'),
            $this->requireUuid($this->payload, 'branch_id', 'Branch ID'),
            $this->requireUuid($this->payload, 'device_id', 'Device ID'),
            $this->requireString($this->payload, 'installation_id', 'Installation ID'),
        ] as $error) {
            if ($error !== null) {
                $errors[] = $error;
            }
        }

        return $errors;
    }
}
