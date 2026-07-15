<?php

declare(strict_types=1);

namespace MizaCloud\Core\Http;

/**
 * بناء استجابات JSON الموحّدة — متوافقة مع cloud/docs/contracts.
 */
final class ResponseBuilder
{
    public function success(mixed $data = null, array $meta = [], int $status = 200): Response
    {
        $payload = ['ok' => true];
        if ($data !== null) {
            $payload['data'] = $data;
        }
        if ($meta !== []) {
            $payload['meta'] = $meta;
        }
        return $this->json($payload, $status);
    }

    public function error(
        string $code,
        string $message,
        int $status = 400,
        array $details = [],
        mixed $data = null,
    ): Response {
        $error = [
            'code' => $code,
            'message' => $message,
            'status_code' => $status,
        ];
        if ($details !== []) {
            $error['details'] = $details;
        }
        $payload = [
            'ok' => false,
            'error' => $error,
        ];
        if ($data !== null) {
            $payload['data'] = $data;
        }
        return $this->json($payload, $status);
    }

    public function json(array $payload, int $status = 200): Response
    {
        $encoded = json_encode($payload, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);
        return new Response($status, $encoded);
    }
}
