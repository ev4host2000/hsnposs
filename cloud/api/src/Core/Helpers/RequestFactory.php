<?php

declare(strict_types=1);

namespace MizaCloud\Core\Helpers;

use MizaCloud\Core\Http\Request;

/**
 * بناء Request من PHP SAPI — بدون منطق أعمال.
 */
final class RequestFactory
{
    public static function fromGlobals(): Request
    {
        $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
        $uri = $_SERVER['REQUEST_URI'] ?? '/';
        $path = parse_url($uri, PHP_URL_PATH) ?: '/';

        $headers = [];
        foreach ($_SERVER as $key => $value) {
            if (str_starts_with($key, 'HTTP_')) {
                $name = str_replace('_', '-', substr($key, 5));
                $headers[$name] = is_string($value) ? $value : (string) $value;
            }
        }

        $body = file_get_contents('php://input') ?: null;

        return new Request(
            method: $method,
            path: $path,
            headers: $headers,
            query: $_GET,
            body: $body,
        );
    }
}
