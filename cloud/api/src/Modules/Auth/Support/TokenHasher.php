<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Auth\Support;

final class TokenHasher
{
    public static function hash(string $token): string
    {
        return hash('sha256', $token);
    }

    public static function refreshToken(): string
    {
        return 'rt_' . bin2hex(random_bytes(32));
    }
}
