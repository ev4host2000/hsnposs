<?php
declare(strict_types=1);

/** Minimal HS256 JWT (compatible with Node jsonwebtoken defaults for this app). */

function activation_b64url_encode(string $bin): string
{
    return rtrim(strtr(base64_encode($bin), '+/', '-_'), '=');
}

function activation_b64url_decode(string $str): string
{
    $pad = strlen($str) % 4;
    if ($pad > 0) {
        $str .= str_repeat('=', 4 - $pad);
    }
    return (string) base64_decode(strtr($str, '-_', '+/'), true);
}

function activation_jwt_sign(array $payload, string $secret): string
{
    $header = ['typ' => 'JWT', 'alg' => 'HS256'];
    $segments = [
        activation_b64url_encode((string) json_encode($header, JSON_UNESCAPED_UNICODE)),
        activation_b64url_encode((string) json_encode($payload, JSON_UNESCAPED_UNICODE)),
    ];
    $signing = $segments[0] . '.' . $segments[1];
    $sig = hash_hmac('sha256', $signing, $secret, true);
    return $signing . '.' . activation_b64url_encode($sig);
}

/** @return array<string,mixed>|null */
function activation_jwt_verify(string $token, string $secret): ?array
{
    $parts = explode('.', $token);
    if (count($parts) !== 3) {
        return null;
    }
    $expected = hash_hmac('sha256', $parts[0] . '.' . $parts[1], $secret, true);
    $sig = activation_b64url_decode($parts[2]);
    if ($sig === '' || !hash_equals($expected, $sig)) {
        return null;
    }
    $payload = json_decode(activation_b64url_decode($parts[1]), true);
    if (!is_array($payload)) {
        return null;
    }
    if (isset($payload['exp']) && time() >= (int) $payload['exp']) {
        return null;
    }
    return $payload;
}
