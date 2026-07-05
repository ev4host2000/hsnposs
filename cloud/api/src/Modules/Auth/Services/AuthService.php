<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Auth\Services;

use DateTimeImmutable;
use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Modules\Auth\Repositories\AuthRepository;
use MizaCloud\Modules\Auth\Support\TokenHasher;
use MizaCloud\Modules\Auth\Validators\LoginValidator;
use MizaCloud\Modules\Auth\Validators\LogoutValidator;
use MizaCloud\Modules\Auth\Validators\RefreshValidator;
use Throwable;

final class AuthService
{
    public function __construct(
        private readonly AuthRepository $repository,
        private readonly JwtService $jwt,
        private readonly RoleScopeResolver $scopes,
        private readonly Logger $logger,
        private readonly int $accessTtl,
        private readonly int $refreshTtl,
    ) {}

    /** @param array<string, mixed> $payload */
    public function login(array $payload, Request $request): array
    {
        $validator = new LoginValidator($payload);
        if ($validator->failed()) {
            throw new HttpException('validation_error', 'Validation failed', 400, [
                'fields' => $validator->messages(),
            ]);
        }

        $companyId = (string) $payload['company_id'];
        $branchId = (string) $payload['branch_id'];
        $deviceId = (string) $payload['device_id'];
        $installationId = (string) $payload['installation_id'];
        $username = (string) $payload['username'];
        $password = (string) $payload['password'];

        $companyStatus = $this->repository->findCompanyStatus($companyId);
        if ($companyStatus === null) {
            throw new HttpException('invalid_credentials', 'Invalid username or password', 401);
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

        $device = $this->repository->findDevice($deviceId, $companyId, $installationId);
        if ($device === null) {
            throw new HttpException('validation_error', 'Device not found', 400, [
                'fields' => ['device_id' => 'Device not registered'],
            ]);
        }
        if (($device['status'] ?? '') !== 'active' || $device['revoked_at'] !== null) {
            throw new HttpException('device_revoked', 'Device is revoked', 403);
        }

        $user = $this->repository->findUserForLogin($companyId, $username);
        if ($user === null || !password_verify($password, $user->passwordHash)) {
            $this->logger->warning('auth.login.failed', ['company_id' => $companyId, 'username' => $username]);
            throw new HttpException('invalid_credentials', 'Invalid username or password', 401);
        }

        if ($user->accountStatus !== 'active') {
            throw new HttpException('account_disabled', 'Account is disabled', 403);
        }

        if (!$this->repository->userHasBranchAccess($user->id, $branchId, $companyId)) {
            throw new HttpException('forbidden', 'User has no access to this branch', 403);
        }

        $roleScopes = $this->scopes->scopesForRole($user->role);
        $now = new DateTimeImmutable('now');
        $refreshExpires = $now->modify('+' . $this->refreshTtl . ' seconds');
        $accessExpires = $now->modify('+' . $this->accessTtl . ' seconds');

        $ip = $this->clientIp($request);
        $userAgent = $request->headers['User-Agent'] ?? $request->headers['user-agent'] ?? null;

        $this->repository->beginTransaction();
        try {
            $sessionId = $this->repository->createUserSession(
                $deviceId,
                $companyId,
                $branchId,
                $user->id,
                $ip,
                $userAgent,
                $refreshExpires,
            );

            $access = $this->jwt->issueAccessToken(
                $user->id,
                $sessionId,
                $companyId,
                $branchId,
                $deviceId,
                $roleScopes,
            );

            $refreshPlain = TokenHasher::refreshToken();
            $this->repository->createApiToken(
                TokenHasher::hash($access['token']),
                $user->id,
                $companyId,
                $sessionId,
                $roleScopes,
                $accessExpires,
            );
            $this->repository->createRefreshToken(
                TokenHasher::hash($refreshPlain),
                $sessionId,
                $companyId,
                $user->id,
                $refreshExpires,
            );
            $this->repository->updateUserLastLogin($user->id);
            $this->repository->touchDeviceLastSeen($deviceId);
            $this->repository->commit();
        } catch (Throwable $e) {
            $this->repository->rollBack();
            throw $e;
        }

        $this->logger->info('auth.login.success', [
            'user_id' => $user->id,
            'company_id' => $companyId,
            'device_id' => $deviceId,
            'session_id' => $sessionId,
        ]);

        return [
            'session_id' => $sessionId,
            'device_id' => $deviceId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'user_id' => $user->id,
            'session_type' => 'user',
            'access_token' => $access['token'],
            'refresh_token' => $refreshPlain,
            'token_type' => 'Bearer',
            'expires_in' => $access['expires_in'],
            'expires_at' => $access['expires_at'],
            'user' => $user->publicProfile(),
        ];
    }

    /** @param array<string, mixed> $payload */
    public function refresh(array $payload): array
    {
        $validator = new RefreshValidator($payload);
        if ($validator->failed()) {
            throw new HttpException('validation_error', 'Validation failed', 400, [
                'fields' => $validator->messages(),
            ]);
        }

        $refreshPlain = (string) $payload['refresh_token'];
        $deviceId = (string) $payload['device_id'];
        $installationId = (string) $payload['installation_id'];

        $stored = $this->repository->findRefreshTokenByHash(TokenHasher::hash($refreshPlain));
        if ($stored === null) {
            throw new HttpException('refresh_token_invalid', 'Refresh token is invalid', 401);
        }

        if ($stored['replaced_by_id'] !== null) {
            $this->logger->warning('auth.refresh.reuse_detected', ['token_id' => $stored['id']]);
            $this->repository->revokeSession((string) $stored['device_session_id']);
            $this->repository->revokeApiTokensForSession((string) $stored['device_session_id']);
            $this->repository->revokeRefreshTokensForSession((string) $stored['device_session_id']);
            throw new HttpException('session_compromised', 'Refresh token reuse detected', 401);
        }

        if ($stored['revoked_at'] !== null) {
            throw new HttpException('refresh_token_invalid', 'Refresh token is invalid', 401);
        }

        if (strtotime((string) $stored['expires_at']) <= time()) {
            throw new HttpException('refresh_token_expired', 'Refresh token expired', 401);
        }

        if (($stored['session_revoked_at'] ?? null) !== null) {
            throw new HttpException('refresh_token_invalid', 'Session is no longer active', 401);
        }

        if (($stored['device_status'] ?? '') !== 'active' || ($stored['device_revoked_at'] ?? null) !== null) {
            throw new HttpException('device_revoked', 'Device is revoked', 403);
        }

        if ((string) $stored['device_id'] !== $deviceId) {
            throw new HttpException('refresh_token_invalid', 'Device mismatch', 401);
        }

        $companyId = (string) $stored['company_id'];
        $device = $this->repository->findDevice($deviceId, $companyId, $installationId);
        if ($device === null) {
            throw new HttpException('refresh_token_invalid', 'Device mismatch', 401);
        }

        $session = $this->repository->findSession((string) $stored['device_session_id']);
        if ($session === null) {
            throw new HttpException('refresh_token_invalid', 'Session not found', 401);
        }

        $userId = (string) ($stored['user_id'] ?? $session['user_id'] ?? '');
        $user = $this->repository->findUserById($userId);
        if ($user === null || $user->accountStatus !== 'active') {
            throw new HttpException('account_disabled', 'Account is disabled', 403);
        }

        $roleScopes = $this->scopes->scopesForRole($user->role);
        $sessionId = (string) $stored['device_session_id'];
        $branchId = (string) $session['branch_id'];
        $now = new DateTimeImmutable('now');
        $refreshExpires = $now->modify('+' . $this->refreshTtl . ' seconds');
        $accessExpires = $now->modify('+' . $this->accessTtl . ' seconds');

        $this->repository->beginTransaction();
        try {
            $access = $this->jwt->issueAccessToken(
                $user->id,
                $sessionId,
                $companyId,
                $branchId,
                $deviceId,
                $roleScopes,
            );
            $newRefreshPlain = TokenHasher::refreshToken();
            $newRefreshId = $this->repository->createRefreshToken(
                TokenHasher::hash($newRefreshPlain),
                $sessionId,
                $companyId,
                $user->id,
                $refreshExpires,
            );
            $this->repository->markRefreshTokenReplaced((string) $stored['id'], $newRefreshId);
            $this->repository->revokeApiTokensForSession($sessionId);
            $this->repository->createApiToken(
                TokenHasher::hash($access['token']),
                $user->id,
                $companyId,
                $sessionId,
                $roleScopes,
                $accessExpires,
            );
            $this->repository->touchSession($sessionId);
            $this->repository->touchDeviceLastSeen($deviceId);
            $this->repository->commit();
        } catch (Throwable $e) {
            $this->repository->rollBack();
            throw $e;
        }

        $this->logger->info('auth.refresh.success', ['user_id' => $user->id, 'session_id' => $sessionId]);

        return [
            'access_token' => $access['token'],
            'refresh_token' => $newRefreshPlain,
            'token_type' => 'Bearer',
            'expires_in' => $access['expires_in'],
            'expires_at' => $access['expires_at'],
        ];
    }

    /** @param array<string, mixed> $payload */
    public function logout(string $accessToken, array $payload): array
    {
        $claims = $this->authenticateAccessToken($accessToken);
        if (!in_array('auth:session', $claims['scopes'] ?? [], true)) {
            throw new HttpException('forbidden', 'Insufficient scope', 403);
        }

        $validator = new LogoutValidator($payload);
        if ($validator->failed()) {
            throw new HttpException('validation_error', 'Validation failed', 400, [
                'fields' => $validator->messages(),
            ]);
        }

        $sessionId = (string) ($claims['session_id'] ?? '');
        $userId = (string) ($claims['sub'] ?? '');
        $companyId = (string) ($claims['company_id'] ?? '');

        if ($sessionId === '') {
            throw new HttpException('unauthorized', 'Invalid session', 401);
        }

        $revokeAll = (bool) ($payload['revoke_all_sessions'] ?? false);

        if ($revokeAll) {
            $this->repository->revokeAllUserSessions($userId, $companyId);
        } else {
            $this->repository->revokeSession($sessionId);
            $this->repository->revokeApiTokensForSession($sessionId);
            $this->repository->revokeRefreshTokensForSession($sessionId);
        }

        if (!empty($payload['refresh_token'])) {
            $stored = $this->repository->findRefreshTokenByHash(
                TokenHasher::hash((string) $payload['refresh_token']),
            );
            if ($stored !== null) {
                $this->repository->revokeRefreshToken((string) $stored['id']);
            }
        }

        $this->logger->info('auth.logout', [
            'user_id' => $userId,
            'session_id' => $sessionId,
            'revoke_all' => $revokeAll,
        ]);

        return ['revoked' => true];
    }

    public function me(string $accessToken): array
    {
        $claims = $this->authenticateAccessToken($accessToken);
        $sessionId = (string) ($claims['session_id'] ?? '');
        $userId = (string) ($claims['sub'] ?? '');

        $session = $this->repository->findSession($sessionId);
        if ($session === null || $session['revoked_at'] !== null) {
            throw new HttpException('unauthorized', 'Session is not active', 401);
        }

        if (($session['device_status'] ?? '') !== 'active' || ($session['device_revoked_at'] ?? null) !== null) {
            throw new HttpException('device_revoked', 'Device is revoked', 403);
        }

        $user = $this->repository->findUserById($userId);
        if ($user === null) {
            throw new HttpException('unauthorized', 'User not found', 401);
        }

        return [
            'session_id' => $sessionId,
            'user' => $user->publicProfile(),
            'company_id' => (string) ($claims['company_id'] ?? ''),
            'branch_id' => (string) ($claims['branch_id'] ?? ''),
            'device_id' => (string) ($claims['device_id'] ?? ''),
            'scopes' => array_values($claims['scopes'] ?? []),
        ];
    }

    /** @return array<string, mixed> */
    private function authenticateAccessToken(string $accessToken): array
    {
        if ($accessToken === '') {
            throw new HttpException('unauthorized', 'Authorization required', 401);
        }

        $claims = $this->jwt->decode($accessToken);
        $stored = $this->repository->findApiTokenByHash(TokenHasher::hash($accessToken));
        if ($stored === null || $stored['revoked_at'] !== null) {
            throw new HttpException('unauthorized', 'Access token revoked', 401);
        }

        return $claims;
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
