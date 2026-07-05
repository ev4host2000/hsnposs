<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Validators;

use MizaCloud\Modules\Auth\Support\Uuid;

/** Shared pull query validation for catalog sync endpoints. */
final class CatalogPullValidator extends SyncValidator
{
    /** @param array<string, mixed> $query */
    public function __construct(private readonly array $query) {}

    /** @return list<string> */
    protected function errors(): array
    {
        $errors = [];

        foreach ([
            $this->requireUuid($this->query, 'company_id', 'Company ID'),
        ] as $error) {
            if ($error !== null) {
                $errors[] = $error;
            }
        }

        $branchId = $this->query['branch_id'] ?? null;
        if ($branchId !== null && $branchId !== '' && is_string($branchId) && !Uuid::isValid($branchId)) {
            $errors[] = 'branch_id:Branch ID must be a valid UUID';
        }

        if (!isset($this->query['since_sequence']) && !isset($this->query['cursor'])) {
            $errors[] = 'since_sequence:since_sequence or cursor is required';
        }

        if (isset($this->query['since_sequence']) && !is_numeric($this->query['since_sequence'])) {
            $errors[] = 'since_sequence:since_sequence must be numeric';
        }

        if (isset($this->query['limit']) && (!is_numeric($this->query['limit']) || (int) $this->query['limit'] < 1)) {
            $errors[] = 'limit:limit must be a positive integer';
        }

        return $errors;
    }
}
