<?php

declare(strict_types=1);

namespace MizaCloud\Core\Http;

/**
 * استجابة HTTP خام.
 */
final class Response
{
    /** @param array<string, string> $headers */
    public function __construct(
        public readonly int $statusCode,
        public readonly string $body,
        public readonly array $headers = ['Content-Type' => 'application/json; charset=utf-8'],
    ) {}

    public function send(): void
    {
        http_response_code($this->statusCode);
        foreach ($this->headers as $name => $value) {
            header("{$name}: {$value}");
        }
        echo $this->body;
    }
}
