<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Invoices\Services;

use MizaCloud\Modules\Invoices\Repositories\InvoiceRepository;

final class InvoiceService
{
    public function __construct(private readonly InvoiceRepository $repository) {}
}
