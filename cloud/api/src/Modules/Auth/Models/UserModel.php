<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Auth\Models;

final class UserModel
{
    /** @param array<string, mixed> $row */
    public static function fromRow(array $row): self
    {
        return new self(
            id: (string) $row['id'],
            companyId: (string) $row['company_id'],
            defaultBranchId: (string) $row['default_branch_id'],
            username: (string) $row['username'],
            fullName: (string) $row['full_name'],
            role: (string) $row['role'],
            accountStatus: (string) $row['account_status'],
            passwordHash: (string) $row['password_hash'],
        );
    }

    public function __construct(
        public readonly string $id,
        public readonly string $companyId,
        public readonly string $defaultBranchId,
        public readonly string $username,
        public readonly string $fullName,
        public readonly string $role,
        public readonly string $accountStatus,
        public readonly string $passwordHash,
    ) {}

    /** @return array<string, mixed> */
    public function publicProfile(): array
    {
        return [
            'id' => $this->id,
            'username' => $this->username,
            'full_name' => $this->fullName,
            'role' => $this->role,
        ];
    }
}
