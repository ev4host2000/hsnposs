<?php

declare(strict_types=1);

namespace MizaCloud\Modules\PublicApi\Services;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Modules\Admin\Repositories\AdminBetaRepository;
use MizaCloud\Modules\Admin\Repositories\AdminRepository;

final class PublicBetaService
{
    public function __construct(
        private readonly AdminBetaRepository $beta,
        private readonly AdminRepository $tenants,
    ) {}

    /** @param array<string, mixed> $payload */
    public function submitSignup(array $payload): array
    {
        $storeName = trim((string) ($payload['store_name'] ?? ''));
        $email = strtolower(trim((string) ($payload['email'] ?? '')));
        $ownerName = trim((string) ($payload['owner_name'] ?? ''));
        $phone = trim((string) ($payload['phone'] ?? ''));
        $message = trim((string) ($payload['message'] ?? ''));
        $voucherCode = trim((string) ($payload['voucher_code'] ?? ''));
        $planCode = strtolower(trim((string) ($payload['plan_code'] ?? 'business')));

        if (strlen($storeName) < 2) {
            throw new HttpException('validation_error', 'Store name is required', 400);
        }
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            throw new HttpException('validation_error', 'Invalid email', 400);
        }
        if ($ownerName === '') {
            $ownerName = $email;
        }

        if ($this->tenants->emailExists($email)) {
            throw new HttpException('conflict', 'Email is already registered', 409);
        }

        if ($this->beta->pendingSignupByEmail($email)) {
            throw new HttpException('conflict', 'A pending signup request already exists for this email', 409);
        }

        if ($voucherCode !== '') {
            $voucher = $this->beta->findVoucherByCode($voucherCode);
            if ($voucher === null) {
                throw new HttpException('validation_error', 'Invalid voucher code', 400);
            }
            if ($voucher['expires_at'] !== null && strtotime((string) $voucher['expires_at']) < time()) {
                throw new HttpException('validation_error', 'Voucher has expired', 400);
            }
            if ((int) $voucher['used_count'] >= (int) $voucher['max_uses']) {
                throw new HttpException('validation_error', 'Voucher usage limit reached', 400);
            }
            $planCode = (string) $voucher['plan_code'];
        }

        $plan = $this->tenants->findPlanByCode($planCode);
        if ($plan === null) {
            throw new HttpException('validation_error', 'Unknown plan', 400);
        }

        $id = $this->beta->createSignupRequest(
            storeName: $storeName,
            email: $email,
            ownerName: $ownerName,
            phone: $phone !== '' ? $phone : null,
            message: $message !== '' ? $message : null,
            planCode: $planCode,
            voucherCode: $voucherCode !== '' ? strtoupper($voucherCode) : null,
        );

        return [
            'request_id' => $id,
            'status' => 'pending',
            'message' => 'تم استلام طلبك — سنتواصل معك بعد المراجعة',
        ];
    }

    /** @param array<string, mixed> $payload */
    public function validateVoucher(array $payload): array
    {
        $code = trim((string) ($payload['code'] ?? ''));
        if ($code === '') {
            throw new HttpException('validation_error', 'code is required', 400);
        }

        $voucher = $this->beta->findVoucherByCode($code);
        if ($voucher === null) {
            throw new HttpException('not_found', 'Invalid voucher', 404);
        }

        $valid = (int) $voucher['used_count'] < (int) $voucher['max_uses'];
        if ($voucher['expires_at'] !== null && strtotime((string) $voucher['expires_at']) < time()) {
            $valid = false;
        }

        return [
            'code' => (string) $voucher['code'],
            'plan_code' => (string) $voucher['plan_code'],
            'valid' => $valid,
            'remaining_uses' => max(0, (int) $voucher['max_uses'] - (int) $voucher['used_count']),
        ];
    }
}
