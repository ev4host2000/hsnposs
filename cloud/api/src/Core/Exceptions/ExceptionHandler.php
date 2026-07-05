<?php

declare(strict_types=1);

namespace MizaCloud\Core\Exceptions;

use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Core\Logging\Logger;
use Throwable;

/**
 * يحوّل الاستثناءات إلى استجابة JSON موحّدة.
 */
final class ExceptionHandler
{
    public function __construct(
        private readonly ResponseBuilder $responses,
        private readonly Logger $logger,
        private readonly bool $debug,
    ) {}

    public function handle(Throwable $e, Request $request): Response
    {
        if ($e instanceof HttpException) {
            return $this->responses->error(
                $e->errorCode,
                $e->getMessage(),
                $e->statusCode,
                $e->details,
            );
        }

        $this->logger->error($e->getMessage(), [
            'path' => $request->path,
            'method' => $request->method,
            'exception' => $e::class,
        ]);

        $message = $this->debug ? $e->getMessage() : 'Internal server error';
        return $this->responses->error('internal_error', $message, 500);
    }
}
