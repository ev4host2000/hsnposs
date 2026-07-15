<?php

declare(strict_types=1);

namespace MizaCloud\Core\Exceptions;

use Exception;

/**
 * استثناء HTTP — يُترجم إلى Response عبر Handler.
 */
class HttpException extends Exception
{
    public function __construct(
        public readonly string $errorCode,
        string $message,
        public readonly int $statusCode = 400,
        public readonly array $details = [],
        public readonly mixed $data = null,
        ?Exception $previous = null,
    ) {
        parent::__construct($message, $statusCode, $previous);
    }
}
