<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Devices\Services;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Modules\Auth\Services\RoleScopeResolver;
use MizaCloud\Modules\Devices\Models\DeviceModel;
use MizaCloud\Modules\Devices\Repositories\DeviceRepository;
use MizaCloud\Modules\Devices\Support\BearerToken;
use MizaCloud\Modules\Devices\Validators\HeartbeatValidator;
use MizaCloud\Modules\Devices\Validators\RegisterDeviceValidator;
use Throwable;

final class DeviceService
{
    public function __construct(
        private readonly DeviceRepository $repository,
        private readonly DeviceTokenService $tokens,
        private readonly BearerToken $bearer,
        private readonly RoleScopeResolver $scopes,
        private readonly Logger $logger,
    ) {}

    /**
     * @param array<string, mixed> $payload
     * @return array{data: array<string, mixed>, status: int}
     */
    public function register(array $payload, Request $request): array
    {
        $claims = $this->bearer->authenticate($request, ['devices:register']);

        $validator = new RegisterDeviceValidator($payload);
        if ($validator->failed()) {
            throw new HttpException('validation_error', 'Validation failed', 400, [
                'fields' => $validator->messages(),
            ]);
        }

        $companyId = (string) $payload['company_id'];
        $branchId = (string) $payload['branch_id'];
        $installationId = (string) $payload['installation_id'];
        $userId = (string) ($payload['registered_by_user_id'] ?? $claims['sub'] ?? '');

        $this->assertCompanyHeader($request, $companyId);
        $this->assertBranchHeader($request, $branchId);

        if ($userId === '' || ($claims['sub'] ?? '') !== $userId) {
            $userId = (string) ($claims['sub'] ?? '');
        }

        if (($claims['company_id'] ?? '') !== $companyId) {
            throw new HttpException('forbidden', 'Company mismatch', 403);
        }

        $companyStatus = $this->repository->findCompanyStatus($companyId);
        if ($companyStatus === null) {
            throw new HttpException('validation_error', 'Company not found', 400);
        }
        if ($companyStatus !== 'active') {
            throw new HttpException('company_suspended', 'Company is suspended', 403);
        }

        $branch = $this->repository->findBranch($companyId, $branchId);
        if ($branch === null || ($branch['status'] ?? '') !== 'active') {
            throw new HttpException('validation_error', 'Invalid branch', 400, [
                'fields' => ['branch_id' => 'Branch not found or inactive'],
            ]);
        }

        $platform = $this->normalizePlatform((string) $payload['platform']);
        $deviceModel = new DeviceModel(
            id: '',
            companyId: $companyId,
            installationId: $installationId,
            deviceFingerprint: (string) $payload['device_fingerprint'],
            platform: $platform,
            deviceName: (string) $payload['device_name'],
            osName: (string) $payload['os_name'],
            osUser: isset($payload['os_user']) ? (string) $payload['os_user'] : null,
            appVersion: isset($payload['app_version']) ? (string) $payload['app_version'] : null,
            status: 'active',
            registeredAt: gmdate('Y-m-d H:i:s'),
            lastSeenAt: null,
            revokedAt: null,
            registeredByUserId: $userId !== '' ? $userId : null,
            rowVersion: 0,
        );

        $existing = $this->repository->findByInstallationId($installationId);
        $httpStatus = 201;

        if ($existing !== null) {
            if ((string) $existing['company_id'] !== $companyId) {
                throw new HttpException('installation_conflict', 'Installation ID belongs to another company', 409);
            }
            if (($existing['status'] ?? '') !== 'active' || $existing['revoked_at'] !== null) {
                throw new HttpException('device_revoked', 'Device is revoked', 403);
            }

            $deviceId = (string) $existing['id'];
            $this->repository->updateDeviceMetadata(
                $deviceId,
                $deviceModel->deviceFingerprint,
                $deviceModel->platform,
                $deviceModel->deviceName,
                $deviceModel->osName,
                $deviceModel->osUser,
                $deviceModel->appVersion,
            );
            $existing = $this->repository->findById($deviceId, $companyId) ?? $existing;
            $httpStatus = 200;
        } else {
            $maxDevices = $this->repository->maxDevicesForCompany($companyId);
            if ($maxDevices !== null && $this->repository->countActiveDevices($companyId) >= $maxDevices) {
                throw new HttpException('device_limit_reached', 'Device limit reached for subscription plan', 403);
            }

            $this->repository->beginTransaction();
            try {
                $deviceId = $this->repository->createDevice($deviceModel);
                $this->repository->commit();
                $existing = $this->repository->findById($deviceId, $companyId);
            } catch (Throwable $e) {
                $this->repository->rollBack();
                throw $e;
            }
        }

        if ($existing === null) {
            throw new HttpException('internal_error', 'Device registration failed', 500);
        }

        $role = $this->repository->findUserRole($userId) ?? 'owner';
        $deviceScopes = $this->scopes->scopesForRole($role);

        $tokenBundle = $this->tokens->issueDeviceSessionTokens(
            $deviceId,
            $companyId,
            $branchId,
            $userId !== '' ? $userId : null,
            $deviceScopes,
            $this->clientIp($request),
            $request->headers['User-Agent'] ?? $request->headers['user-agent'] ?? null,
        );

        $model = DeviceModel::fromRow($existing, true);

        $this->logger->info('devices.register', [
            'device_id' => $deviceId,
            'company_id' => $companyId,
            'installation_id' => $installationId,
            'reused' => $httpStatus === 200,
        ]);

        \MizaCloud\Modules\Admin\Services\OpsAuditWriter::recordAction(
            \MizaCloud\Modules\Admin\Support\OpsAuditActions::DEVICE_ACTIVATION,
            'success',
            [
                'organization_id' => $companyId,
                'branch_id' => $branchId,
                'device_id' => $deviceId,
                'installation_id' => $installationId,
                'user_id' => $userId !== '' ? $userId : null,
                'entity' => 'device',
                'entity_id' => $deviceId,
                'metadata' => ['reused' => $httpStatus === 200],
            ],
            $request,
        );

        return [
            'status' => $httpStatus,
            'data' => array_merge($model->toArray(), $tokenBundle),
        ];
    }

    /** @param array<string, mixed> $payload */
    public function heartbeat(array $payload, Request $request): array
    {
        $claims = $this->bearer->authenticate($request);
        $this->assertDeviceContext($request, $claims);

        $validator = new HeartbeatValidator($payload);
        if ($validator->failed()) {
            throw new HttpException('validation_error', 'Validation failed', 400, [
                'fields' => $validator->messages(),
            ]);
        }

        $deviceId = (string) ($claims['device_id'] ?? $claims['sub'] ?? '');
        $device = $this->repository->findById($deviceId);
        if ($device === null) {
            throw new HttpException('not_found', 'Device not found', 404);
        }
        if (($device['status'] ?? '') !== 'active' || $device['revoked_at'] !== null) {
            throw new HttpException('device_revoked', 'Device is revoked', 403);
        }

        $appVersion = isset($payload['app_version']) ? (string) $payload['app_version'] : null;
        $lastSeen = $this->repository->touchLastSeen($deviceId, $appVersion);

        return [
            'last_seen_at' => gmdate('Y-m-d\TH:i:s.v\Z', strtotime($lastSeen) ?: time()),
        ];
    }

    public function me(Request $request): array
    {
        $claims = $this->bearer->authenticate($request);
        $this->assertDeviceContext($request, $claims);

        $deviceId = (string) ($claims['device_id'] ?? $claims['sub'] ?? '');
        $companyId = (string) ($claims['company_id'] ?? '');

        $device = $this->repository->findById($deviceId, $companyId !== '' ? $companyId : null);
        if ($device === null) {
            throw new HttpException('not_found', 'Device not found', 404);
        }
        if (($device['status'] ?? '') !== 'active' || $device['revoked_at'] !== null) {
            throw new HttpException('device_revoked', 'Device is revoked', 403);
        }

        return DeviceModel::fromRow($device, true)->toArray(includeFingerprint: true);
    }

    /** @param array<string, mixed> $claims */
    private function assertDeviceContext(Request $request, array $claims): void
    {
        $headerDeviceId = $request->headers['X-Device-ID']
            ?? $request->headers['x-device-id']
            ?? '';
        $claimDeviceId = (string) ($claims['device_id'] ?? $claims['sub'] ?? '');

        if ($headerDeviceId !== '' && $claimDeviceId !== '' && $headerDeviceId !== $claimDeviceId) {
            throw new HttpException('forbidden', 'Device header mismatch', 403);
        }
    }

    private function assertCompanyHeader(Request $request, string $companyId): void
    {
        $header = $request->headers['X-Company-ID'] ?? $request->headers['x-company-id'] ?? '';
        if ($header !== '' && $header !== $companyId) {
            throw new HttpException('forbidden', 'Company header mismatch', 403);
        }
    }

    private function assertBranchHeader(Request $request, string $branchId): void
    {
        $header = $request->headers['X-Branch-ID'] ?? $request->headers['x-branch-id'] ?? '';
        if ($header !== '' && $header !== $branchId) {
            throw new HttpException('forbidden', 'Branch header mismatch', 403);
        }
    }

    private function normalizePlatform(string $platform): string
    {
        return match (strtolower($platform)) {
            'desktop', 'windows' => 'windows',
            'android' => 'android',
            'ios' => 'ios',
            'web' => 'web',
            default => $platform,
        };
    }

    private function clientIp(Request $request): ?string
    {
        $forwarded = $request->headers['X-Forwarded-For'] ?? $request->headers['x-forwarded-for'] ?? null;
        if (is_string($forwarded) && $forwarded !== '') {
            return trim(explode(',', $forwarded)[0]);
        }

        $remote = $_SERVER['REMOTE_ADDR'] ?? null;

        return is_string($remote) ? $remote : null;
    }
}
