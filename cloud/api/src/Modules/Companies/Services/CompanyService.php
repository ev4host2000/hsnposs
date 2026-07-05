<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Companies\Services;

use MizaCloud\Modules\Companies\Repositories\CompanyRepository;

final class CompanyService
{
    public function __construct(private readonly CompanyRepository $repository) {}
}
