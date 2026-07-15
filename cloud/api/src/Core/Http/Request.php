<?php

declare(strict_types=1);

namespace MizaCloud\Core\Http;

/**
 * غلاف طلب HTTP — يُملأ من $_SERVER / php://input لاحقاً.
 */
final class Request
{
    /**
     * @param array<string, string> $headers
     * @param array<string, array{name: string, tmp_name: string, size: int, error: int, type: string}> $files
     */
    public function __construct(
        public readonly string $method,
        public readonly string $path,
        public readonly array $headers = [],
        public readonly array $query = [],
        public readonly ?string $body = null,
        public readonly array $attributes = [],
        public readonly array $files = [],
    ) {}

    public function attribute(string $key, mixed $default = null): mixed
    {
        return $this->attributes[$key] ?? $default;
    }

    public function withAttribute(string $key, mixed $value): self
    {
        $attributes = $this->attributes;
        $attributes[$key] = $value;
        return new self(
            $this->method,
            $this->path,
            $this->headers,
            $this->query,
            $this->body,
            $attributes,
            $this->files,
        );
    }
}
