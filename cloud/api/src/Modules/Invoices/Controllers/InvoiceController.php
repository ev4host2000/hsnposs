<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Invoices\Controllers;

use MizaCloud\Core\Http\Controller;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Modules\Invoices\Services\InvoiceService;

final class InvoiceController extends Controller
{
    public function __construct(ResponseBuilder $responses, private readonly InvoiceService $service)
    {
        parent::__construct($responses);
    }
}
