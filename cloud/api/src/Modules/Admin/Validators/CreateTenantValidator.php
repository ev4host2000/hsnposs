<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Admin\Validators;

use MizaCloud\Core\Exceptions\HttpException;

final class CreateTenantValidator
{
    /** @param array<string, mixed> $payload */
    public function validate(array $payload): array
    {
        $storeName = $this->requireString($payload, 'store_name', 'Store name');
        $email = strtolower($this->requireString($payload, 'email', 'Email'));
        $password = $this->requireString($payload, 'password', 'Password');
        $ownerName = trim((string) ($payload['owner_name'] ?? ''));
        $planCode = strtolower(trim((string) ($payload['plan_code'] ?? 'business')));

        if (strlen($storeName) < 2 || strlen($storeName) > 120) {
            throw new HttpException('validation_error', 'Store name must be 2-120 characters', 400);
        }

        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            throw new HttpException('validation_error', 'Invalid email address', 400);
        }

        if (strlen($password) < 8) {
            throw new HttpException('validation_error', 'Password must be at least 8 characters', 400);
        }

        if ($planCode === '') {
            $planCode = 'business';
        }

        return [
            'store_name' => $storeName,
            'email' => $email,
            'password' => $password,
            'owner_name' => $ownerName !== '' ? $ownerName : $email,
            'plan_code' => $planCode,
        ];
    }

    /** @param array<string, mixed> $payload */
    private function requireString(array $payload, string $key, string $label): string
    {
        $value = $payload[$key] ?? null;
        if (!is_string($value) || trim($value) === '') {
            throw new HttpException('validation_error', "{$label} is required", 400);
        }

        return trim($value);
    }
}
