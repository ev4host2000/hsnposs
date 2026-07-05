<?php

declare(strict_types=1);

namespace MizaCloud\Core\Http;

/**
 * قاعدة Controllers — تستقبل ResponseBuilder من Container لاحقاً.
 */
abstract class Controller
{
    public function __construct(protected readonly ResponseBuilder $responses) {}
}
