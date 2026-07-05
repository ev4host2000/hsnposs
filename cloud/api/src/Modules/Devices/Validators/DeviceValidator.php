<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Devices\Validators;

use MizaCloud\Core\Helpers\Validator;
use MizaCloud\Modules\Auth\Support\Uuid;

abstract class DeviceValidator extends Validator
{
    public function failed(): bool
    {
        return !$this->passes();
    }

    /** @return array<string, string> */
    public function messages(): array
    {
        $errors = [];
        foreach ($this->errors() as $error) {
            if (str_contains($error, ':')) {
                [$field, $message] = explode(':', $error, 2);
                $errors[trim($field)] = trim($message);
            } else {
                $errors['_'] = $error;
            }
        }

        return $errors;
    }

    protected function requireUuid(array $payload, string $field, string $label): ?string
    {
        $value = $payload[$field] ?? null;
        if (!is_string($value) || trim($value) === '') {
            return "{$field}:{$label} is required";
        }
        if (!Uuid::isValid($value)) {
            return "{$field}:{$label} must be a valid UUID";
        }

        return null;
    }

    protected function requireString(array $payload, string $field, string $label): ?string
    {
        $value = $payload[$field] ?? null;
        if (!is_string($value) || trim($value) === '') {
            return "{$field}:{$label} is required";
        }

        return null;
    }
}
