<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Invoices\Validators;

use MizaCloud\Core\Helpers\Validator;

final class InvoiceValidator extends Validator
{
    public function __construct(private readonly array $payload) {}
}
