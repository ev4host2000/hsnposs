<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Admin\Services;

use MizaCloud\Core\Config\Config;
use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Mail\SmtpMailer;
use MizaCloud\Modules\Admin\Repositories\AdminBetaRepository;
use MizaCloud\Modules\Admin\Repositories\AdminMonitoringRepository;
use MizaCloud\Modules\Admin\Repositories\AdminObservabilityRepository;
use MizaCloud\Modules\Admin\Repositories\AdminRepository;
use MizaCloud\Modules\Admin\Repositories\AdminSyncRepository;
use MizaCloud\Modules\Admin\Services\OpsAuditWriter;
use MizaCloud\Modules\Admin\Support\BetaApprovalEmailBuilder;
use MizaCloud\Modules\Admin\Support\OpsAuditActions;
use MizaCloud\Modules\Admin\Support\OpsAuditContext;
use MizaCloud\Modules\Admin\Support\PlatformAdminBearer;
use MizaCloud\Modules\Admin\Support\WelcomeCardBuilder;
use MizaCloud\Modules\Admin\Validators\CreateTenantValidator;
use MizaCloud\Modules\Auth\Repositories\AuthRepository;
use MizaCloud\Modules\Auth\Services\JwtService;
use MizaCloud\Modules\Auth\Support\TokenHasher;
use MizaCloud\Modules\Auth\Support\Uuid;
use Throwable;
use DateTimeImmutable;

final class AdminService
{
    private const SCOPES = ['platform:read', 'platform:write'];

    public function __construct(
        private readonly AdminRepository $repository,
        private readonly AdminSyncRepository $syncRepository,
        private readonly AdminObservabilityRepository $observabilityRepository,
        private readonly AdminMonitoringRepository $monitoringRepository,
        private readonly AdminBetaRepository $betaRepository,
        private readonly PlatformAdminBearer $bearer,
        private readonly JwtService $jwt,
        private readonly CreateTenantValidator $createTenantValidator,
        private readonly WelcomeCardBuilder $welcomeCard,
        private readonly BetaApprovalEmailBuilder $approvalEmail,
        private readonly SmtpMailer $mailer,
        private readonly Config $config,
        private readonly AuthRepository $authRepository,
        private readonly OpsAuditWriter $auditWriter,
    ) {}

    /** @param array<string, mixed> $payload */
    public function login(array $payload, ?Request $request = null): array
    {
        $admin = $this->config->get('admin', []);
        if (!is_array($admin)) {
            $admin = [];
        }

        $configuredEmail = strtolower(trim((string) ($admin['email'] ?? '')));
        $passwordHash = (string) ($admin['password_hash'] ?? '');
        $accessTtl = (int) ($admin['access_ttl'] ?? 3600);

        if ($configuredEmail === '' || $passwordHash === '') {
            throw new HttpException('service_unavailable', 'Platform admin is not configured', 503);
        }

        $email = strtolower(trim((string) ($payload['email'] ?? '')));
        $password = (string) ($payload['password'] ?? '');

        if ($email === '' || $password === '') {
            $this->auditAuth($request, OpsAuditActions::LOGIN_FAILED, 'failure', $email, 'missing_credentials');
            throw new HttpException('validation_error', 'Email and password are required', 400);
        }

        if ($email !== $configuredEmail || !password_verify($password, $passwordHash)) {
            $this->auditAuth($request, OpsAuditActions::LOGIN_FAILED, 'failure', $email, 'invalid_credentials');
            throw new HttpException('unauthorized', 'Invalid credentials', 401);
        }

        $this->authRepository->revokeAllActivePlatformAdminTokens();

        $issued = $this->jwt->issuePlatformAdminToken(self::SCOPES, $accessTtl);

        $expires = (new DateTimeImmutable('now'))->modify('+' . $accessTtl . ' seconds');
        if ($expires === false) {
            throw new HttpException('internal_error', 'Failed to compute token expiry', 500);
        }

        $this->authRepository->createPlatformAdminToken(
            $issued['jti'],
            TokenHasher::hash($issued['token']),
            self::SCOPES,
            $expires,
        );

        $this->auditAuth($request, OpsAuditActions::LOGIN, 'success', $configuredEmail);

        return [
            'access_token' => $issued['token'],
            'token_type' => 'Bearer',
            'expires_in' => $issued['expires_in'],
            'expires_at' => $issued['expires_at'],
            'admin' => [
                'email' => $configuredEmail,
            ],
        ];
    }

    public function me(Request $request): array
    {
        $claims = $this->bearer->authenticate($request, ['platform:read']);
        $admin = $this->config->get('admin', []);
        if (!is_array($admin)) {
            $admin = [];
        }

        return [
            'subject' => (string) ($claims['sub'] ?? ''),
            'scopes' => $claims['scopes'] ?? [],
            'email' => (string) ($admin['email'] ?? ''),
        ];
    }

    public function logout(Request $request): array
    {
        $token = $this->bearer->extract($request);
        if ($token === null) {
            throw new HttpException('unauthorized', 'Authorization required', 401);
        }

        $this->bearer->authenticate($request, ['platform:read']);
        $this->authRepository->revokePlatformAdminTokenByHash(TokenHasher::hash($token));
        $this->auditAuth($request, OpsAuditActions::LOGOUT, 'success', 'platform_admin');

        return ['revoked' => true];
    }

    public function listCompanies(Request $request): array
    {
        $this->bearer->authenticate($request, ['platform:read']);
        $search = trim((string) ($request->query['q'] ?? ''));
        if ($search === '') {
            $search = null;
        }

        return [
            'companies' => $this->repository->listCompanies($search),
            'search' => $search,
        ];
    }

    public function getCompany(Request $request, string $companyId): array
    {
        $this->bearer->authenticate($request, ['platform:read']);
        if (!Uuid::isValid($companyId)) {
            throw new HttpException('validation_error', 'Invalid company id', 400);
        }

        $company = $this->repository->findCompany($companyId);
        if ($company === null) {
            throw new HttpException('not_found', 'Company not found', 404);
        }

        return ['company' => $company];
    }

    public function listDevices(Request $request, string $companyId): array
    {
        $this->bearer->authenticate($request, ['platform:read']);
        if (!Uuid::isValid($companyId)) {
            throw new HttpException('validation_error', 'Invalid company id', 400);
        }

        if ($this->repository->findCompany($companyId) === null) {
            throw new HttpException('not_found', 'Company not found', 404);
        }

        return [
            'devices' => $this->repository->listDevicesForCompany($companyId),
        ];
    }

    public function listPlans(Request $request): array
    {
        $this->bearer->authenticate($request, ['platform:read']);

        return [
            'plans' => $this->repository->listPlans(),
        ];
    }

    /** @param array<string, mixed> $payload */
    public function createTenant(Request $request, array $payload): array
    {
        $this->bearer->authenticate($request, ['platform:write']);
        $validated = $this->createTenantValidator->validate($payload);

        if ($this->repository->emailExists($validated['email'])) {
            throw new HttpException('conflict', 'Email is already registered', 409);
        }

        $plan = $this->repository->findPlanByCode($validated['plan_code']);
        if ($plan === null) {
            throw new HttpException('validation_error', 'Unknown subscription plan', 400);
        }

        $passwordHash = password_hash($validated['password'], PASSWORD_BCRYPT);
        if ($passwordHash === false) {
            throw new HttpException('internal_error', 'Failed to hash password', 500);
        }

        $created = $this->repository->createTenant(
            storeName: $validated['store_name'],
            email: $validated['email'],
            ownerName: $validated['owner_name'],
            passwordHash: $passwordHash,
            planId: (string) $plan['id'],
        );

        $apiUrl = $this->apiBaseUrl();
        $welcomeCard = $this->welcomeCard->build(
            storeName: $validated['store_name'],
            email: $validated['email'],
            companyId: $created['company_id'],
            branchId: $created['branch_id'],
            planCode: (string) $plan['code'],
            apiUrl: $apiUrl,
        );

        $this->auditOps($request, OpsAuditActions::ORG_CREATED, 'success', [
            'organization_id' => $created['company_id'],
            'branch_id' => $created['branch_id'],
            'entity' => 'organization',
            'entity_id' => $created['company_id'],
            'metadata' => ['store_name' => $validated['store_name'], 'plan_code' => $plan['code']],
        ]);

        return [
            'tenant' => [
                'company_id' => $created['company_id'],
                'branch_id' => $created['branch_id'],
                'owner_user_id' => $created['user_id'],
                'subscription_id' => $created['subscription_id'],
                'store_name' => $validated['store_name'],
                'email' => $validated['email'],
                'plan_code' => $plan['code'],
                'api_url' => $apiUrl,
                'welcome_card' => $welcomeCard,
            ],
        ];
    }

    public function welcomeCard(Request $request, string $companyId): array
    {
        $this->bearer->authenticate($request, ['platform:read']);
        $company = $this->requireCompany($companyId);

        return [
            'welcome_card' => $this->welcomeCard->build(
                storeName: (string) $company['name'],
                email: (string) ($company['owner_email'] ?? ''),
                companyId: (string) $company['id'],
                branchId: (string) ($company['default_branch_id'] ?? ''),
                planCode: (string) ($company['plan_code'] ?? 'business'),
                apiUrl: $this->apiBaseUrl(),
            ),
        ];
    }

    /** @param array<string, mixed> $payload */
    public function updateCompanyStatus(Request $request, string $companyId, array $payload): array
    {
        $this->bearer->authenticate($request, ['platform:write']);
        $this->requireCompany($companyId);

        $status = strtolower(trim((string) ($payload['status'] ?? '')));
        if (!in_array($status, ['active', 'suspended', 'closed'], true)) {
            throw new HttpException('validation_error', 'Status must be active, suspended, or closed', 400);
        }

        $this->repository->updateCompanyStatus($companyId, $status);
        $this->auditOps($request, OpsAuditActions::ORG_UPDATED, 'success', [
            'organization_id' => $companyId,
            'entity' => 'organization',
            'entity_id' => $companyId,
            'reason' => 'status=' . $status,
            'metadata' => ['status' => $status],
        ]);

        return [
            'company_id' => $companyId,
            'status' => $status,
        ];
    }

    /** @param array<string, mixed> $payload */
    public function deleteCompany(Request $request, string $companyId, array $payload): array
    {
        $this->bearer->authenticate($request, ['platform:write']);
        $company = $this->requireCompany($companyId);

        $confirmName = trim((string) ($payload['confirm_name'] ?? ''));
        $companyName = trim((string) ($company['name'] ?? ''));
        if ($confirmName === '' || mb_strtolower($confirmName) !== mb_strtolower($companyName)) {
            throw new HttpException(
                'validation_error',
                'confirm_name must exactly match the store name',
                400,
            );
        }

        $confirmDelete = strtolower(trim((string) ($payload['confirm_delete'] ?? '')));
        if ($confirmDelete !== 'delete') {
            throw new HttpException(
                'validation_error',
                'confirm_delete must be "delete"',
                400,
            );
        }

        try {
            $result = $this->repository->deleteCompanyCompletely($companyId);
            $this->auditOps($request, OpsAuditActions::ORG_DELETED, 'success', [
                'organization_id' => $companyId,
                'entity' => 'organization',
                'entity_id' => $companyId,
                'metadata' => $result,
            ]);

            return $result;
        } catch (\PDOException $e) {
            $this->auditOps($request, OpsAuditActions::ORG_DELETED, 'failure', [
                'organization_id' => $companyId,
                'entity' => 'organization',
                'entity_id' => $companyId,
                'error_code' => 'delete_failed',
                'error_message' => $e->getMessage(),
            ]);
            throw new HttpException(
                'internal_error',
                'Failed to delete company: ' . $e->getMessage(),
                500,
            );
        }
    }

    /** @param array<string, mixed> $payload */
    public function updateCompanySubscription(Request $request, string $companyId, array $payload): array
    {
        $this->bearer->authenticate($request, ['platform:write']);
        $this->requireCompany($companyId);

        $planCode = strtolower(trim((string) ($payload['plan_code'] ?? '')));
        if ($planCode === '') {
            throw new HttpException('validation_error', 'plan_code is required', 400);
        }

        $plan = $this->repository->findPlanByCode($planCode);
        if ($plan === null) {
            throw new HttpException('validation_error', 'Unknown subscription plan', 400);
        }

        $this->repository->updateActiveSubscriptionPlan($companyId, (string) $plan['id']);
        $this->auditOps($request, OpsAuditActions::SUBSCRIPTION_UPDATED, 'success', [
            'organization_id' => $companyId,
            'entity' => 'subscription',
            'entity_id' => $companyId,
            'metadata' => ['plan_code' => $plan['code']],
        ]);

        return [
            'company_id' => $companyId,
            'plan_code' => $plan['code'],
            'plan_name' => $plan['name'],
            'max_devices' => (int) $plan['max_devices'],
        ];
    }

    /** @param array<string, mixed> $payload */
    public function resetOwnerPassword(Request $request, string $companyId, array $payload): array
    {
        $this->bearer->authenticate($request, ['platform:write']);
        $this->requireCompany($companyId);

        $password = (string) ($payload['password'] ?? '');
        if (strlen($password) < 8) {
            throw new HttpException('validation_error', 'Password must be at least 8 characters', 400);
        }

        $passwordHash = password_hash($password, PASSWORD_BCRYPT);
        if ($passwordHash === false) {
            throw new HttpException('internal_error', 'Failed to hash password', 500);
        }

        $owners = $this->authRepository->findOwnersByCompany($companyId);
        if ($owners === []) {
            throw new HttpException('not_found', 'Owner user not found', 404);
        }

        // Hash + Auth revoke in one transaction (RAP-P0-05). No company-wide SQL.
        $this->authRepository->beginTransaction();
        try {
            if (!$this->repository->resetOwnerPassword($companyId, $passwordHash)) {
                $this->authRepository->rollBack();
                throw new HttpException('not_found', 'Owner user not found', 404);
            }

            foreach ($owners as $owner) {
                $this->authRepository->revokeUserAccessAfterPasswordChange(
                    (string) $owner['id'],
                    (string) $owner['company_id'],
                );
            }

            $this->authRepository->commit();
        } catch (HttpException $e) {
            throw $e;
        } catch (Throwable $e) {
            $this->authRepository->rollBack();
            throw $e;
        }

        $this->auditOps($request, OpsAuditActions::PASSWORD_RESET, 'success', [
            'organization_id' => $companyId,
            'entity' => 'user',
            'entity_id' => $companyId,
            'reason' => 'owner_password_reset',
        ]);

        return [
            'company_id' => $companyId,
            'password_reset' => true,
        ];
    }

    /** @return array<string, mixed> */
    private function requireCompany(string $companyId): array
    {
        if (!Uuid::isValid($companyId)) {
            throw new HttpException('validation_error', 'Invalid company id', 400);
        }

        $company = $this->repository->findCompany($companyId);
        if ($company === null) {
            throw new HttpException('not_found', 'Company not found', 404);
        }

        return $company;
    }

    private function apiBaseUrl(): string
    {
        $app = $this->config->get('app', []);
        if (!is_array($app)) {
            return 'https://api.mizapos.com';
        }

        $url = trim((string) ($app['url'] ?? ''));

        return $url !== '' ? rtrim($url, '/') : 'https://api.mizapos.com';
    }

    public function dashboardOverview(Request $request): array
    {
        $this->bearer->authenticate($request, ['platform:read']);

        $metrics = $this->observabilityRepository->platformMetrics();
        $sync = $this->syncRepository->globalOverview();
        $alerts = $this->observabilityRepository->listAlerts();
        $database = $this->observabilityRepository->databaseHealth();

        $status = 'healthy';
        if (!$database['connected']) {
            $status = 'critical';
        } else {
            foreach ($alerts as $alert) {
                if (($alert['severity'] ?? '') === 'critical') {
                    $status = 'critical';
                    break;
                }
                if (($alert['severity'] ?? '') === 'warning' && $status !== 'critical') {
                    $status = 'degraded';
                }
            }
        }

        $pendingSignups = $this->betaRepository->countSignupRequests('pending');
        $recentSignups = array_slice(
            $this->betaRepository->listSignupRequests('pending'),
            0,
            8,
        );

        return [
            'status' => $status,
            'timestamp' => gmdate('Y-m-d\TH:i:s\Z'),
            'summary' => [
                'active_companies' => (int) ($metrics['active_companies'] ?? 0),
                'total_companies' => (int) ($metrics['total_companies'] ?? 0),
                'active_devices' => (int) ($metrics['active_devices'] ?? 0),
                'pending_signups' => $pendingSignups,
                'pending_sync_queue' => (int) ($sync['pending_queue'] ?? 0),
                'failed_sync_queue' => (int) ($sync['failed_queue'] ?? 0),
                'stale_devices' => (int) ($sync['stale_devices'] ?? 0),
                'pending_conflicts' => (int) ($sync['pending_conflicts'] ?? 0),
                'subscriptions_expiring_30d' => $this->observabilityRepository->countExpiringSubscriptions(30),
            ],
            'alerts' => array_slice($alerts, 0, 10),
            'recent_signups' => $recentSignups,
            'mail' => [
                'configured' => $this->mailer->isConfigured(),
            ],
        ];
    }

    public function syncOverview(Request $request): array
    {
        $this->bearer->authenticate($request, ['platform:read']);

        return [
            'overview' => $this->syncRepository->globalOverview(),
            'stale_devices' => $this->syncRepository->listStaleDevices(30),
        ];
    }

    public function companySyncHealth(Request $request, string $companyId): array
    {
        $this->bearer->authenticate($request, ['platform:read']);
        $company = $this->requireCompany($companyId);

        return [
            'company_id' => $companyId,
            'company_name' => (string) $company['name'],
            'health' => $this->syncRepository->companySyncHealth($companyId),
        ];
    }

    public function listSyncFailures(Request $request): array
    {
        $this->bearer->authenticate($request, ['platform:read']);
        $companyId = trim((string) ($request->query['company_id'] ?? ''));
        if ($companyId !== '' && !Uuid::isValid($companyId)) {
            throw new HttpException('validation_error', 'Invalid company_id', 400);
        }

        $limit = (int) ($request->query['limit'] ?? 50);

        return [
            'failures' => $this->syncRepository->listFailures(
                $companyId !== '' ? $companyId : null,
                $limit,
            ),
        ];
    }

    public function listSyncConflicts(Request $request): array
    {
        $this->bearer->authenticate($request, ['platform:read']);
        $companyId = trim((string) ($request->query['company_id'] ?? ''));
        if ($companyId !== '' && !Uuid::isValid($companyId)) {
            throw new HttpException('validation_error', 'Invalid company_id', 400);
        }

        $status = trim((string) ($request->query['status'] ?? ''));
        if ($status !== '' && !in_array($status, ['pending', 'resolved'], true)) {
            throw new HttpException('validation_error', 'status must be pending or resolved', 400);
        }

        $limit = (int) ($request->query['limit'] ?? 50);

        return [
            'conflicts' => $this->syncRepository->listConflicts(
                $companyId !== '' ? $companyId : null,
                $status !== '' ? $status : null,
                $limit,
            ),
        ];
    }

    public function observabilityOverview(Request $request): array
    {
        $this->bearer->authenticate($request, ['platform:read']);

        $database = $this->observabilityRepository->databaseHealth();
        $storage = $this->observabilityRepository->storageHealth($this->storageRoot());
        $logs = $this->observabilityRepository->logMetrics($this->logDirectory());
        $alerts = $this->observabilityRepository->listAlerts();

        $overall = 'healthy';
        if (!$database['connected']) {
            $overall = 'critical';
        } elseif ($alerts !== [] || $storage['warnings'] !== []) {
            $overall = 'degraded';
        }

        return [
            'status' => $overall,
            'timestamp' => gmdate('Y-m-d\TH:i:s\Z'),
            'metrics' => $this->observabilityRepository->platformMetrics(),
            'database' => $database,
            'storage' => $storage,
            'logs' => $logs,
            'alerts' => $alerts,
            'application' => $this->applicationInfo(),
        ];
    }

    public function monitoringOverview(Request $request): array
    {
        $this->bearer->authenticate($request, ['platform:read']);

        return $this->monitoringRepository->snapshot([
            'company_id' => $request->query['company_id'] ?? null,
            'branch_id' => $request->query['branch_id'] ?? null,
            'device_id' => $request->query['device_id'] ?? null,
            'date_from' => $request->query['date_from'] ?? null,
            'date_to' => $request->query['date_to'] ?? null,
            'sync_type' => $request->query['sync_type'] ?? null,
            'status' => $request->query['status'] ?? null,
        ]);
    }

    public function listAuditLogs(Request $request): array
    {
        $this->bearer->authenticate($request, ['platform:read']);

        $companyId = trim((string) ($request->query['company_id'] ?? ''));
        if ($companyId !== '' && !Uuid::isValid($companyId)) {
            throw new HttpException('validation_error', 'Invalid company_id', 400);
        }

        $action = trim((string) ($request->query['action'] ?? ''));
        $limit = (int) ($request->query['limit'] ?? 50);
        $offset = (int) ($request->query['offset'] ?? 0);

        $companyFilter = $companyId !== '' ? $companyId : null;
        $actionFilter = $action !== '' ? $action : null;

        return [
            'total' => $this->observabilityRepository->countAuditLogs($companyFilter, $actionFilter),
            'limit' => max(1, min($limit, 200)),
            'offset' => max(0, $offset),
            'entries' => $this->observabilityRepository->listAuditLogs(
                $companyFilter,
                $actionFilter,
                $limit,
                $offset,
            ),
        ];
    }

    public function listSignupRequests(Request $request): array
    {
        $this->bearer->authenticate($request, ['platform:read']);
        $status = trim((string) ($request->query['status'] ?? ''));

        return [
            'requests' => $this->betaRepository->listSignupRequests(
                $status !== '' ? $status : null,
            ),
        ];
    }

    /** @param array<string, mixed> $payload */
    public function approveSignupRequest(Request $request, string $requestId, array $payload): array
    {
        $this->bearer->authenticate($request, ['platform:write']);
        if (!Uuid::isValid($requestId)) {
            throw new HttpException('validation_error', 'Invalid request id', 400);
        }

        $signup = $this->betaRepository->findSignupRequest($requestId);
        if ($signup === null) {
            throw new HttpException('not_found', 'Signup request not found', 404);
        }
        if (($signup['status'] ?? '') !== 'pending') {
            throw new HttpException('conflict', 'Request is not pending', 409);
        }

        $password = (string) ($payload['password'] ?? '');
        if (strlen($password) < 8) {
            $password = bin2hex(random_bytes(6)) . 'A1!';
        }

        if ($this->repository->emailExists((string) $signup['email'])) {
            throw new HttpException('conflict', 'Email is already registered', 409);
        }

        $planCode = (string) ($signup['desired_plan_code'] ?? 'business');
        $plan = $this->repository->findPlanByCode($planCode);
        if ($plan === null) {
            throw new HttpException('validation_error', 'Unknown subscription plan', 400);
        }

        $passwordHash = password_hash($password, PASSWORD_BCRYPT);
        if ($passwordHash === false) {
            throw new HttpException('internal_error', 'Failed to hash password', 500);
        }

        $created = $this->repository->createTenant(
            storeName: (string) $signup['store_name'],
            email: (string) $signup['email'],
            ownerName: (string) $signup['owner_name'],
            passwordHash: $passwordHash,
            planId: (string) $plan['id'],
        );

        $voucherCode = (string) ($signup['voucher_code'] ?? '');
        if ($voucherCode !== '') {
            $voucher = $this->betaRepository->findVoucherByCode($voucherCode);
            if ($voucher !== null) {
                $this->betaRepository->incrementVoucherUse((string) $voucher['id']);
            }
        }

        $this->betaRepository->markSignupApproved($requestId, $created['company_id']);

        $welcomeCard = $this->welcomeCard->build(
            storeName: (string) $signup['store_name'],
            email: (string) $signup['email'],
            companyId: $created['company_id'],
            branchId: $created['branch_id'],
            planCode: (string) $plan['code'],
            apiUrl: $this->apiBaseUrl(),
        );

        $sendEmail = !array_key_exists('send_email', $payload) || filter_var($payload['send_email'], FILTER_VALIDATE_BOOLEAN);
        $emailResult = ['sent' => false, 'error' => null];
        if ($sendEmail) {
            $mail = $this->approvalEmail->buildApproval(
                storeName: (string) $signup['store_name'],
                email: (string) $signup['email'],
                password: $password,
                planCode: (string) $plan['code'],
                apiUrl: $this->apiBaseUrl(),
            );
            $emailResult = $this->mailer->send(
                (string) $signup['email'],
                $mail['subject'],
                $mail['text'],
                $mail['html'],
            );
        }

        return [
            'request_id' => $requestId,
            'approved' => true,
            'email' => $emailResult,
            'tenant' => [
                'company_id' => $created['company_id'],
                'branch_id' => $created['branch_id'],
                'email' => (string) $signup['email'],
                'initial_password' => $password,
                'welcome_card' => $welcomeCard,
            ],
        ];
    }

    /** @param array<string, mixed> $payload */
    public function rejectSignupRequest(Request $request, string $requestId, array $payload): array
    {
        $this->bearer->authenticate($request, ['platform:write']);
        if (!Uuid::isValid($requestId)) {
            throw new HttpException('validation_error', 'Invalid request id', 400);
        }

        $signup = $this->betaRepository->findSignupRequest($requestId);
        if ($signup === null) {
            throw new HttpException('not_found', 'Signup request not found', 404);
        }
        if (($signup['status'] ?? '') !== 'pending') {
            throw new HttpException('conflict', 'Request is not pending', 409);
        }

        $reason = trim((string) ($payload['reason'] ?? 'Rejected by ops'));
        $this->betaRepository->markSignupRejected($requestId, $reason);

        $sendEmail = !array_key_exists('send_email', $payload) || filter_var($payload['send_email'], FILTER_VALIDATE_BOOLEAN);
        $emailResult = ['sent' => false, 'error' => null];
        if ($sendEmail) {
            $mail = $this->approvalEmail->buildRejection(
                storeName: (string) $signup['store_name'],
                email: (string) $signup['email'],
                reason: $reason,
            );
            $emailResult = $this->mailer->send(
                (string) $signup['email'],
                $mail['subject'],
                $mail['text'],
                $mail['html'],
            );
        }

        return [
            'request_id' => $requestId,
            'rejected' => true,
            'reason' => $reason,
            'email' => $emailResult,
        ];
    }

    public function listVouchers(Request $request): array
    {
        $this->bearer->authenticate($request, ['platform:read']);

        return ['vouchers' => $this->betaRepository->listVouchers()];
    }

    /** @param array<string, mixed> $payload */
    public function createVoucher(Request $request, array $payload): array
    {
        $this->bearer->authenticate($request, ['platform:write']);

        $code = strtoupper(trim((string) ($payload['code'] ?? '')));
        if (strlen($code) < 4) {
            throw new HttpException('validation_error', 'Voucher code must be at least 4 characters', 400);
        }

        $planCode = strtolower(trim((string) ($payload['plan_code'] ?? 'business')));
        $plan = $this->repository->findPlanByCode($planCode);
        if ($plan === null) {
            throw new HttpException('validation_error', 'Unknown plan', 400);
        }

        $maxUses = (int) ($payload['max_uses'] ?? 1);
        $expiresAt = trim((string) ($payload['expires_at'] ?? ''));
        $notes = trim((string) ($payload['notes'] ?? ''));

        if ($this->betaRepository->findVoucherByCode($code) !== null) {
            throw new HttpException('conflict', 'Voucher code already exists', 409);
        }

        $id = $this->betaRepository->createVoucher(
            code: $code,
            planCode: $planCode,
            maxUses: $maxUses,
            expiresAt: $expiresAt !== '' ? $expiresAt : null,
            notes: $notes !== '' ? $notes : null,
        );

        return [
            'voucher_id' => $id,
            'code' => $code,
            'plan_code' => $planCode,
        ];
    }

    /** @param array<string, mixed> $payload */
    public function extendCompanySubscription(Request $request, string $companyId, array $payload): array
    {
        $this->bearer->authenticate($request, ['platform:write']);
        $this->requireCompany($companyId);

        $days = (int) ($payload['days'] ?? 0);
        if ($days < 1 || $days > 3650) {
            throw new HttpException('validation_error', 'days must be between 1 and 3650', 400);
        }

        if (!$this->betaRepository->extendSubscriptionPeriod($companyId, $days)) {
            throw new HttpException('not_found', 'Active subscription not found', 404);
        }

        $company = $this->repository->findCompany($companyId);

        return [
            'company_id' => $companyId,
            'extended_days' => $days,
            'company' => $company,
        ];
    }

    public function revokeDevice(Request $request, string $deviceId): array
    {
        $this->bearer->authenticate($request, ['platform:write']);
        if (!Uuid::isValid($deviceId)) {
            throw new HttpException('validation_error', 'Invalid device id', 400);
        }

        $device = $this->repository->findDevice($deviceId);
        if ($device === null) {
            throw new HttpException('not_found', 'Device not found', 404);
        }

        if (($device['revoked_at'] ?? null) !== null || ($device['status'] ?? '') === 'revoked') {
            throw new HttpException('conflict', 'Device is already revoked', 409);
        }

        $this->repository->revokeDevice($deviceId);
        $this->auditOps($request, OpsAuditActions::DEVICE_REVOCATION, 'success', [
            'organization_id' => (string) $device['company_id'],
            'device_id' => $deviceId,
            'entity' => 'device',
            'entity_id' => $deviceId,
        ]);

        return [
            'device_id' => $deviceId,
            'company_id' => (string) $device['company_id'],
            'revoked' => true,
        ];
    }

    /** @param array<string, mixed> $extra */
    private function auditOps(Request $request, string $action, string $status, array $extra = []): void
    {
        $this->auditWriter->write(array_merge(OpsAuditContext::fromRequest($request), [
            'action' => $action,
            'status' => $status,
            'user_name' => 'platform_admin',
            'role' => 'platform_admin',
            'platform' => 'miza_cloud_admin',
            'trigger_source' => 'admin_ops',
        ], $extra));
    }

    private function auditAuth(?Request $request, string $action, string $status, string $email, ?string $reason = null): void
    {
        $base = $request !== null ? OpsAuditContext::fromRequest($request) : [
            'platform' => 'miza_cloud_admin',
            'trigger_source' => 'admin_ops',
        ];
        $this->auditWriter->write(array_merge($base, [
            'action' => $action,
            'status' => $status,
            'user_name' => $email !== '' ? $email : 'unknown',
            'role' => 'platform_admin',
            'entity' => 'platform_admin',
            'reason' => $reason,
            'error_code' => $status === 'failure' ? ($reason ?? 'auth_failed') : null,
        ]));
    }

  /** @return array<string, mixed> */
    private function applicationInfo(): array
    {
        $app = $this->config->get('app', []);
        if (!is_array($app)) {
            $app = [];
        }

        return [
            'name' => (string) ($app['name'] ?? 'Miza Cloud API'),
            'environment' => (string) ($app['env'] ?? 'production'),
            'api_version' => (string) ($app['api_version'] ?? 'v1'),
            'php_version' => PHP_VERSION,
            'url' => $this->apiBaseUrl(),
        ];
    }

    private function storageRoot(): string
    {
        return $this->apiRootPath() . '/storage';
    }

    private function logDirectory(): string
    {
        $logging = $this->config->get('logging', []);
        if (!is_array($logging)) {
            return $this->storageRoot() . '/logs';
        }

        $path = str_replace('\\', '/', (string) ($logging['path'] ?? 'storage/logs'));
        if (str_starts_with($path, '/')) {
            return $path;
        }

        return $this->apiRootPath() . '/' . $path;
    }

    private function apiRootPath(): string
    {
        return dirname(__DIR__, 4);
    }
}
