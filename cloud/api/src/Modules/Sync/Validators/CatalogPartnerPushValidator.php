<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Validators;

abstract class CatalogPartnerPushValidator extends CatalogNamedEntityPushValidator
{
    /** @param array<string, mixed>|null $payload @return list<string> */
    protected function validatePayload(?array $payload, string $prefix): array
    {
        $errors = parent::validatePayload($payload, $prefix);
        if (!is_array($payload)) {
            return $errors;
        }

        if (array_key_exists('credit_limit', $payload) && !is_numeric($payload['credit_limit'])) {
            $errors[] = "{$prefix}.payload_json.credit_limit:credit_limit must be numeric";
        }

        if (array_key_exists('overdue_alert_days', $payload)
            && $payload['overdue_alert_days'] !== null
            && !is_numeric($payload['overdue_alert_days'])) {
            $errors[] = "{$prefix}.payload_json.overdue_alert_days:overdue_alert_days must be numeric";
        }

        return $errors;
    }
}
