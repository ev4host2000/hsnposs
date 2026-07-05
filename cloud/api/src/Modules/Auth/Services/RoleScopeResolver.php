<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Auth\Services;

/**
 * Scopes افتراضية حسب الدور — cloud/docs/contracts/00-conventions.md
 */
final class RoleScopeResolver
{
  /** @var list<string> */
    private const ALL_SCOPES = [
        'auth:session',
        'devices:register',
        'devices:read',
        'devices:admin',
        'company:read',
        'company:write',
        'branches:read',
        'branches:write',
        'users:read',
        'users:write',
        'catalog:read',
        'catalog:write',
        'invoices:read',
        'invoices:write',
        'sync:push',
        'sync:pull',
        'notifications:read',
    ];

    /** @return list<string> */
    public function scopesForRole(string $role): array
    {
        return match ($role) {
            'owner', 'admin' => self::ALL_SCOPES,
            'accountant' => [
                'auth:session',
                'company:read',
                'branches:read',
                'catalog:read',
                'catalog:write',
                'invoices:read',
                'invoices:write',
                'sync:push',
                'sync:pull',
                'notifications:read',
            ],
            'cashier' => [
                'auth:session',
                'company:read',
                'branches:read',
                'catalog:read',
                'invoices:write',
                'sync:push',
                'sync:pull',
            ],
            'distributor' => [
                'auth:session',
                'company:read',
                'branches:read',
                'catalog:read',
                'sync:pull',
            ],
            default => ['auth:session', 'catalog:read'],
        };
    }
}
