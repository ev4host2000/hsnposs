<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Invoices\Models;

final class InvoiceModel
{
    public function __construct(public readonly string $id = '') {}
}
