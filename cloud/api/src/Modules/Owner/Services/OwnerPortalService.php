<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Owner\Services;

use DateTimeImmutable;
use MizaCloud\Core\Config\Config;
use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Request;
use MizaCloud\Modules\Auth\Repositories\AuthRepository;
use MizaCloud\Modules\Auth\Services\JwtService;
use MizaCloud\Modules\Auth\Services\RoleScopeResolver;
use MizaCloud\Modules\Auth\Support\TokenHasher;
use MizaCloud\Modules\Auth\Support\Uuid;
use MizaCloud\Modules\Owner\Repositories\OwnerDashboardRepository;
use MizaCloud\Modules\Owner\Support\OwnerPortalBearer;

final class OwnerPortalService
{
    /** @var list<string> */
    private const PORTAL_SCOPES = [
        'company:read',
        'branches:read',
        'devices:read',
        'users:read',
        'catalog:read',
        'invoices:read',
    ];

    public function __construct(
        private readonly OwnerDashboardRepository $repository,
        private readonly OwnerPortalBearer $bearer,
        private readonly AuthRepository $authRepository,
        private readonly JwtService $jwt,
        private readonly RoleScopeResolver $scopes,
        private readonly Config $config,
    ) {}

    /** @param array<string, mixed> $payload */
    public function login(array $payload): array
    {
        $email = strtolower(trim((string) ($payload['email'] ?? '')));
        $password = (string) ($payload['password'] ?? '');
        $companyId = trim((string) ($payload['company_id'] ?? ''));

        if ($email === '' || $password === '') {
            throw new HttpException('validation_error', 'Email and password are required', 400);
        }

        $accounts = $this->repository->findOwnerAccountsByEmail($email);
        if ($accounts === []) {
            throw new HttpException('invalid_credentials', 'Invalid email or password', 401);
        }

        $valid = [];
        foreach ($accounts as $account) {
            if (!password_verify($password, (string) $account['password_hash'])) {
                continue;
            }
            if (($account['account_status'] ?? '') !== 'active') {
                continue;
            }
            if (($account['company_status'] ?? '') !== 'active') {
                continue;
            }
            $valid[] = $account;
        }

        if ($valid === []) {
            throw new HttpException('invalid_credentials', 'Invalid email or password', 401);
        }

        if ($companyId === '' && count($valid) > 1) {
            return [
                'needs_company_selection' => true,
                'companies' => array_map(static fn (array $row): array => [
                    'company_id' => (string) $row['company_id'],
                    'company_name' => (string) $row['company_name'],
                    'branch_id' => (string) $row['branch_id'],
                ], $valid),
            ];
        }

        $selected = $valid[0];
        if ($companyId !== '') {
            foreach ($valid as $account) {
                if ((string) $account['company_id'] === $companyId) {
                    $selected = $account;
                    break;
                }
            }
            if ((string) $selected['company_id'] !== $companyId) {
                throw new HttpException('forbidden', 'No access to selected company', 403);
            }
        }

        return $this->issuePortalToken($selected);
    }

    public function me(Request $request): array
    {
        $claims = $this->bearer->authenticate($request);
        $userId = (string) ($claims['sub'] ?? '');
        $companyId = (string) ($claims['company_id'] ?? '');
        $user = $this->authRepository->findUserById($userId);
        if ($user === null) {
            throw new HttpException('unauthorized', 'User not found', 401);
        }

        return [
            'user' => $user->publicProfile(),
            'company_id' => $companyId,
            'branch_id' => (string) ($claims['branch_id'] ?? ''),
        ];
    }

    public function dashboard(Request $request): array
    {
        $claims = $this->bearer->authenticate($request);
        $companyId = (string) ($claims['company_id'] ?? '');
        if (!Uuid::isValid($companyId)) {
            throw new HttpException('validation_error', 'Invalid company', 400);
        }

        return [
            'summary' => $this->repository->dashboardSummary($companyId),
            'subscription' => $this->repository->subscriptionInfo($companyId),
        ];
    }

    public function devices(Request $request): array
    {
        $claims = $this->bearer->authenticate($request);
        $companyId = (string) ($claims['company_id'] ?? '');

        return [
            'devices' => $this->repository->listDevices($companyId),
        ];
    }

    /** @param array<string, mixed> $account */
    private function issuePortalToken(array $account): array
    {
        $userId = (string) $account['user_id'];
        $companyId = (string) $account['company_id'];
        $branchId = (string) $account['branch_id'];
        $role = (string) ($account['role'] ?? 'owner');
        $portalScopes = array_values(array_intersect(
            $this->scopes->scopesForRole($role),
            self::PORTAL_SCOPES,
        ));

        $ttl = $this->ownerAccessTtl();
        $issued = $this->jwt->issueOwnerPortalToken(
            $userId,
            $companyId,
            $branchId,
            $portalScopes,
            $ttl,
        );

        $expires = (new DateTimeImmutable('now'))->modify('+' . $ttl . ' seconds');
        if ($expires === false) {
            throw new HttpException('internal_error', 'Failed to compute token expiry', 500);
        }
        $this->authRepository->createApiToken(
            TokenHasher::hash($issued['token']),
            $userId,
            $companyId,
            null,
            $portalScopes,
            $expires,
        );

        return [
            'access_token' => $issued['token'],
            'token_type' => 'Bearer',
            'expires_in' => $issued['expires_in'],
            'expires_at' => $issued['expires_at'],
            'user' => [
                'id' => $userId,
                'email' => (string) $account['email'],
                'full_name' => (string) $account['full_name'],
                'role' => $role,
            ],
            'company' => [
                'id' => $companyId,
                'name' => (string) $account['company_name'],
                'branch_id' => $branchId,
            ],
            'owner_portal_url' => $this->ownerPortalUrl(),
        ];
    }

    private function ownerAccessTtl(): int
    {
        $admin = $this->config->get('owner', []);
        if (!is_array($admin)) {
            return 28800;
        }

        return (int) ($admin['access_ttl'] ?? 28800);
    }

    private function ownerPortalUrl(): string
    {
        $app = $this->config->get('app', []);
        $base = is_array($app) ? rtrim((string) ($app['url'] ?? 'https://api.mizapos.com'), '/') : 'https://api.mizapos.com';

        return $base . '/owner/';
    }
}
