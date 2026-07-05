<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Auth\Validators;

final class LogoutValidator extends AuthValidator
{
    public function __construct(private readonly array $payload) {}

    /** @return list<string> */
    protected function errors(): array
    {
        $errors = [];

        if (isset($this->payload['revoke_all_sessions']) && !is_bool($this->payload['revoke_all_sessions'])) {
            $errors[] = 'revoke_all_sessions:must be boolean';
        }

        if (isset($this->payload['refresh_token']) && !is_string($this->payload['refresh_token'])) {
            $errors[] = 'refresh_token:must be a string';
        }

        return $errors;
    }
}
