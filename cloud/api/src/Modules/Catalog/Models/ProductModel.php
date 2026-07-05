<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Catalog\Models;

final class ProductModel
{
    public function __construct(public readonly string $id = '') {}
}
