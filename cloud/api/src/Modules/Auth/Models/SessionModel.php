<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Auth\Models;

/** Model — جلسة/token DTO لاحقاً. */
final class SessionModel
{
    public function __construct(
        public readonly string $sessionId = '',
        public readonly string $userId = '',
        public readonly string $companyId = '',
        public readonly string $branchId = '',
    ) {}
}
