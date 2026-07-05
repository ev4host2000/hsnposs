<?php

declare(strict_types=1);

namespace MizaCloud\Core\Database;

/**
 * قاعدة Repositories — بدون SQL.
 */
abstract class Repository
{
    public function __construct(protected readonly Connection $db) {}
}
