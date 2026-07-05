<?php

declare(strict_types=1);

namespace MizaCloud\Core\Helpers;

/**
 * Validator base — كل Module يرث أو يستخدمه.
 */
abstract class Validator
{
    /** @return list<string> */
    protected function errors(): array
    {
        return [];
    }

    public function passes(): bool
    {
        return $this->errors() === [];
    }
}
