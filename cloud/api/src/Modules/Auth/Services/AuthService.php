<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Auth\Services;

use DateTimeImmutable;
use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Core\Mail\SmtpMailer;
use MizaCloud\Modules\Auth\Repositories\AuthRepository;
use MizaCloud\Modules\Auth\Support\TokenHasher;
use MizaCloud\Modules\Auth\Validators\LoginValidator;
use MizaCloud\Modules\Auth\Validators\LogoutValidator;
use MizaCloud\Modules\Auth\Validators\PairingLoginValidator;
use MizaCloud\Modules\Auth\Validators\RefreshValidator;
use Throwable;

final class AuthService
{
    public function __construct(
        private readonly AuthRepository $repository,
        private readonly JwtService $jwt,
        private readonly RoleScopeResolver $scopes,
        private readonly Logger $logger,
        private readonly SmtpMailer $mailer,
        private readonly int $accessTtl,
        private readonly int $refreshTtl,
    ) {}

    /** @param array<string, mixed> $payload */
    public function forgotPassword(array $payload): array
    {
        $email = strtolower(trim((string) ($payload['email'] ?? '')));
        if ($email === '' || filter_var($email, FILTER_VALIDATE_EMAIL) === false) {
            throw new HttpException('validation_error', 'Valid email is required', 400);
        }

        if (!$this->mailer->isConfigured()) {
            throw new HttpException('mail_not_configured', 'Password reset email is not available', 503);
        }

        $password = $this->generateTemporaryPassword();
        $passwordHash = password_hash($password, PASSWORD_BCRYPT);
        if ($passwordHash === false) {
            throw new HttpException('internal_error', 'Failed to hash password', 500);
        }

        $owners = $this->repository->findActiveOwnersByEmail($email);
        $updated = 0;

        // Hash + session revoke in one transaction; SMTP stays outside (RAP-P0-05).
        if ($owners !== []) {
            $this->repository->beginTransaction();
            try {
                $updated = $this->repository->updateOwnerPasswordsByEmail($email, $passwordHash);
                if ($updated > 0) {
                    foreach ($owners as $owner) {
                        $this->repository->revokeUserAccessAfterPasswordChange(
                            (string) $owner['id'],
                            (string) $owner['company_id'],
                        );
                    }
                }
                $this->repository->commit();
            } catch (Throwable $e) {
                $this->repository->rollBack();
                throw $e;
            }
        }

        if ($updated > 0) {
            $this->logger->info('auth.password_forgot.updated', [
                'email' => $email,
                'owners_updated' => $updated,
                'company_ids' => array_values(array_unique(array_map(
                    static fn (array $o): string => (string) $o['company_id'],
                    $owners,
                ))),
            ]);

            $mail = $this->buildPasswordResetEmail($email, $password);
            $result = $this->mailer->send(
                $email,
                $mail['subject'],
                $mail['text'],
                $mail['html'],
            );
            if (!$result['sent']) {
                // Password already changed + sessions revoked — do not roll back (safer than restoring old access).
                // Operator/user should retry forgot-password or use Ops reset.
                $this->logger->error('Cloud password reset mail failed', [
                    'email' => $email,
                    'owners_updated' => $updated,
                    'password_already_rotated' => true,
                    'error' => $result['error'],
                ]);
                throw new HttpException(
                    'mail_send_failed',
                    'Could not send reset email. If you did not receive mail, retry later or contact support.',
                    502,
                );
            }

            $this->logger->info('auth.password_forgot.mail_sent', [
                'email' => $email,
                'owners_updated' => $updated,
            ]);
        }

        return [
            'ok' => true,
            'message' => 'If an account exists, a temporary password was sent.',
        ];
    }

    /**
     * RAP-P1-03: high-entropy temporary password (24 chars, mixed classes, no fixed weak suffix).
     */
    private function generateTemporaryPassword(): string
    {
        $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
        $lower = 'abcdefghijkmnopqrstuvwxyz';
        $digits = '23456789';
        $symbols = '!@#$%*?';
        $all = $upper . $lower . $digits . $symbols;

        $pick = static function (string $alphabet): string {
            return $alphabet[random_int(0, strlen($alphabet) - 1)];
        };

        $chars = [
            $pick($upper),
            $pick($lower),
            $pick($digits),
            $pick($symbols),
        ];
        for ($i = 0; $i < 20; $i++) {
            $chars[] = $pick($all);
        }

        for ($i = count($chars) - 1; $i > 0; $i--) {
            $j = random_int(0, $i);
            [$chars[$i], $chars[$j]] = [$chars[$j], $chars[$i]];
        }

        return implode('', $chars);
    }

    /** @return array{subject: string, text: string, html: string} */
    private function buildPasswordResetEmail(string $email, string $password): array
    {
        $subject = 'Miza Cloud — كلمة مرور مؤقتة لمرة واحدة';
        $text = implode("\n", [
            'مرحباً،',
            '',
            'وصلنا طلب إعادة تعيين كلمة مرور حساب Miza Cloud المرتبط بالبريد:',
            "  {$email}",
            '',
            'كلمة المرور المؤقتة (لمرة الدخول الآن فقط):',
            "  {$password}",
            '',
            'مهم:',
            '- سجّل الدخول من تطبيق MizaPos فوراً.',
            '- غيّر كلمة المرور من إعدادات الحساب بعد أول دخول.',
            '- الجلسات السابقة على الأجهزة أُبطلت لأمان حسابك.',
            '- إن لم يصلك هذا البريد أو فشل الإرسال، أعد المحاولة لاحقاً أو تواصل مع الدعم.',
            '',
            'إن لم تطلب إعادة التعيين، غيّر كلمة المرور فوراً وتواصل مع الدعم.',
            '',
            '— فريق MizaPos',
        ]);
        $safeEmail = htmlspecialchars($email, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $safePassword = htmlspecialchars($password, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $html = '<!DOCTYPE html><html lang="ar" dir="rtl"><head><meta charset="UTF-8"></head><body style="font-family:Tahoma,Arial,sans-serif;line-height:1.6;color:#1a2332;">'
            . '<p>وصلنا طلب إعادة تعيين كلمة مرور حساب <strong>Miza Cloud</strong>.</p>'
            . '<p>البريد: <strong>' . $safeEmail . '</strong></p>'
            . '<p>كلمة المرور المؤقتة (لمرة الدخول الآن فقط): <strong>' . $safePassword . '</strong></p>'
            . '<ul>'
            . '<li>سجّل الدخول من تطبيق MizaPos فوراً.</li>'
            . '<li>غيّر كلمة المرور من إعدادات الحساب بعد أول دخول.</li>'
            . '<li>الجلسات السابقة على الأجهزة أُبطلت لأمان حسابك.</li>'
            . '</ul>'
            . '<p style="color:#64748b;font-size:14px;">إن لم تطلب إعادة التعيين، غيّر كلمة المرور فوراً وتواصل مع الدعم.</p>'
            . '</body></html>';

        return ['subject' => $subject, 'text' => $text, 'html' => $html];
    }

    /** @param array<string, mixed> $payload */
    public function login(array $payload, Request $request): array
    {
        $validator = new LoginValidator($payload);
        if ($validator->failed()) {
            throw new HttpException('validation_error', 'Validation failed', 400, [
                'fields' => $validator->messages(),
            ]);
        }

        $companyId = trim((string) ($payload['company_id'] ?? ''));
        $branchId = trim((string) ($payload['branch_id'] ?? ''));
        $deviceId = trim((string) ($payload['device_id'] ?? ''));
        $installationId = trim((string) ($payload['installation_id'] ?? ''));
        $username = (string) $payload['username'];
        $password = (string) $payload['password'];

        // لا نربط الشركة من installation قبل التحقق من كلمة المرور —
        // جهاز قديم على نفس الهاتف كان يفرض متجراً خاطئاً ويرفض بيانات صحيحة.
        $user = null;
        if ($companyId === '' || $branchId === '') {
            $resolved = $this->resolveTenantContext($username, $password, $companyId, $branchId);
            $companyId = $resolved['company_id'];
            $branchId = $resolved['branch_id'];
            $user = $resolved['user'];
        }

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

        if ($deviceId === '' && $installationId !== '') {
            $resolvedDevice = $this->repository->findDeviceByInstallation($companyId, $installationId);
            if ($resolvedDevice !== null) {
                $deviceId = (string) $resolvedDevice['id'];
            }
        }

        if ($deviceId === '') {
            throw new HttpException('device_not_registered', 'Device must be registered before login', 403);
        }

        $device = $this->repository->findDevice($deviceId, $companyId, $installationId);
        if ($device === null) {
            $device = $this->repository->findDeviceByInstallation($companyId, $installationId);
            if ($device === null || (string) $device['id'] !== $deviceId) {
                throw new HttpException('validation_error', 'Device not found', 400, [
                    'fields' => ['device_id' => 'Device not registered'],
                ]);
            }
        }
        if (($device['status'] ?? '') !== 'active' || $device['revoked_at'] !== null) {
            throw new HttpException('device_revoked', 'Device is revoked', 403);
        }

        $user ??= $this->repository->findUserForLogin($companyId, $username);
        if ($user === null || !password_verify($password, $user->passwordHash)) {
            $this->logger->warning('auth.login.failed', ['company_id' => $companyId, 'username' => $username]);
            \MizaCloud\Modules\Admin\Services\OpsAuditWriter::recordAction(
                \MizaCloud\Modules\Admin\Support\OpsAuditActions::LOGIN_FAILED,
                'failure',
                [
                    'organization_id' => $companyId,
                    'branch_id' => $branchId,
                    'device_id' => $deviceId !== '' ? $deviceId : null,
                    'installation_id' => $installationId !== '' ? $installationId : null,
                    'user_name' => $username,
                    'entity' => 'user',
                    'error_code' => 'invalid_credentials',
                ],
                $request,
            );
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

        \MizaCloud\Modules\Admin\Services\OpsAuditWriter::recordAction(
            \MizaCloud\Modules\Admin\Support\OpsAuditActions::LOGIN,
            'success',
            [
                'organization_id' => $companyId,
                'branch_id' => $branchId,
                'device_id' => $deviceId,
                'installation_id' => $installationId !== '' ? $installationId : null,
                'user_id' => $user->id,
                'user_name' => $username,
                'role' => $user->role,
                'session_id' => $sessionId,
                'entity' => 'user',
                'entity_id' => $user->id,
            ],
            $request,
        );

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
        $companyStatus = $this->repository->findCompanyStatus($companyId);
        if ($companyStatus === null || $companyStatus !== 'active') {
            throw new HttpException('company_suspended', 'Company is suspended', 403);
        }

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

        \MizaCloud\Modules\Admin\Services\OpsAuditWriter::recordAction(
            \MizaCloud\Modules\Admin\Support\OpsAuditActions::TOKEN_REFRESH,
            'success',
            [
                'organization_id' => (string) ($stored['company_id'] ?? ''),
                'user_id' => $user->id,
                'device_id' => $deviceId,
                'session_id' => $sessionId,
                'entity' => 'session',
                'entity_id' => $sessionId,
            ],
        );

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

        \MizaCloud\Modules\Admin\Services\OpsAuditWriter::recordAction(
            \MizaCloud\Modules\Admin\Support\OpsAuditActions::LOGOUT,
            'success',
            [
                'organization_id' => $companyId,
                'user_id' => $userId,
                'session_id' => $sessionId,
                'entity' => 'session',
                'entity_id' => $sessionId,
                'metadata' => ['revoke_all' => $revokeAll],
            ],
        );

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

    /**
     * تسجيل دخول مؤقت لربط جهاز جديد — token قصير العمر بصلاحية devices:register فقط.
     *
     * @param array<string, mixed> $payload
     */
    public function loginPairing(array $payload, Request $request): array
    {
        $validator = new PairingLoginValidator($payload);
        if ($validator->failed()) {
            throw new HttpException('validation_error', 'Validation failed', 400, [
                'fields' => $validator->messages(),
            ]);
        }

        $companyId = trim((string) ($payload['company_id'] ?? ''));
        $branchId = trim((string) ($payload['branch_id'] ?? ''));
        $username = (string) $payload['username'];
        $password = (string) $payload['password'];

        $resolved = $this->resolveTenantContext($username, $password, $companyId, $branchId);
        $companyId = $resolved['company_id'];
        $branchId = $resolved['branch_id'];
        $user = $resolved['user'];

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

        $user = $resolved['user'];

        $pairingScopes = ['auth:session', 'devices:register'];
        $now = new DateTimeImmutable('now');
        $accessExpires = $now->modify('+' . $this->accessTtl . ' seconds');
        $pairingSessionId = \MizaCloud\Modules\Auth\Support\Uuid::v4();

        $access = $this->jwt->issueAccessToken(
            $user->id,
            $pairingSessionId,
            $companyId,
            $branchId,
            '',
            $pairingScopes,
        );

        $this->repository->createApiToken(
            TokenHasher::hash($access['token']),
            $user->id,
            $companyId,
            null,
            $pairingScopes,
            $accessExpires,
        );

        $this->logger->info('auth.login_pairing.success', [
            'user_id' => $user->id,
            'company_id' => $companyId,
        ]);

        return [
            'session_id' => $pairingSessionId,
            'device_id' => '',
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'user_id' => $user->id,
            'session_type' => 'pairing',
            'access_token' => $access['token'],
            'token_type' => 'Bearer',
            'expires_in' => $access['expires_in'],
            'expires_at' => $access['expires_at'],
            'user' => $user->publicProfile(),
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

    /**
     * @return array{user: \MizaCloud\Modules\Auth\Models\UserModel, company_id: string, branch_id: string}
     */
    private function resolveTenantContext(
        string $username,
        string $password,
        string $companyId,
        string $branchId,
    ): array {
        $login = trim($username);

        if ($companyId !== '' && $branchId !== '') {
            $user = $this->repository->findUserForLogin($companyId, $login);
            if ($user === null || !password_verify($password, $user->passwordHash)) {
                throw new HttpException('invalid_credentials', 'Invalid username or password', 401);
            }

            return [
                'user' => $user,
                'company_id' => $companyId,
                'branch_id' => $branchId,
            ];
        }

        if (!str_contains($login, '@')) {
            throw new HttpException('invalid_credentials', 'Invalid username or password', 401);
        }

        $accounts = $this->repository->findLoginAccountsByEmail($login);
        $valid = [];

        foreach ($accounts as $row) {
            if ($companyId !== '' && (string) $row['company_id'] !== $companyId) {
                continue;
            }
            if (!password_verify($password, (string) $row['password_hash'])) {
                continue;
            }
            if (($row['account_status'] ?? '') !== 'active') {
                continue;
            }
            if (($row['company_status'] ?? '') !== 'active') {
                continue;
            }
            $valid[] = $row;
        }

        if ($valid === []) {
            throw new HttpException('invalid_credentials', 'Invalid username or password', 401);
        }

        if ($companyId === '' && count($valid) > 1) {
            throw new HttpException('company_selection_required', 'Select a store', 409, [
                'companies' => array_map(static fn (array $row): array => [
                    'company_id' => (string) $row['company_id'],
                    'company_name' => (string) $row['company_name'],
                    'branch_id' => (string) $row['branch_id'],
                ], $valid),
            ]);
        }

        $selected = $valid[0];
        if ($companyId !== '') {
            foreach ($valid as $row) {
                if ((string) $row['company_id'] === $companyId) {
                    $selected = $row;
                    break;
                }
            }
        }

        $resolvedCompanyId = (string) $selected['company_id'];
        $resolvedBranchId = $branchId !== ''
            ? $branchId
            : (string) $selected['branch_id'];

        $user = $this->repository->findUserById((string) $selected['user_id']);
        if ($user === null) {
            throw new HttpException('invalid_credentials', 'Invalid username or password', 401);
        }

        if (!$this->repository->userHasBranchAccess($user->id, $resolvedBranchId, $resolvedCompanyId)) {
            throw new HttpException('forbidden', 'User has no access to this branch', 403);
        }

        return [
            'user' => $user,
            'company_id' => $resolvedCompanyId,
            'branch_id' => $resolvedBranchId,
        ];
    }
}
