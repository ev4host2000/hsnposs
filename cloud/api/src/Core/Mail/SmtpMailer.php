<?php

declare(strict_types=1);

namespace MizaCloud\Core\Mail;

use MizaCloud\Core\Config\Config;
use RuntimeException;

final class SmtpMailer
{
    public function __construct(private readonly Config $config) {}

    public function isConfigured(): bool
    {
        $mail = $this->mailConfig();
        if (!($mail['enabled'] ?? false)) {
            return false;
        }

        return trim((string) ($mail['host'] ?? '')) !== ''
            && trim((string) ($mail['from_address'] ?? '')) !== '';
    }

    /**
     * @return array{sent: bool, error: ?string}
     */
    public function send(
        string $to,
        string $subject,
        string $textBody,
        ?string $htmlBody = null,
    ): array {
        if (!$this->isConfigured()) {
            return ['sent' => false, 'error' => 'mail_not_configured'];
        }

        $to = trim($to);
        if ($to === '' || !filter_var($to, FILTER_VALIDATE_EMAIL)) {
            return ['sent' => false, 'error' => 'invalid_recipient'];
        }

        try {
            $this->deliver($to, $subject, $textBody, $htmlBody);

            return ['sent' => true, 'error' => null];
        } catch (\Throwable $e) {
            return ['sent' => false, 'error' => $e->getMessage()];
        }
    }

  /** @param array<string, mixed> */
    private function mailConfig(): array
    {
        $mail = $this->config->get('mail', []);

        return is_array($mail) ? $mail : [];
    }

    private function deliver(
        string $to,
        string $subject,
        string $textBody,
        ?string $htmlBody,
    ): void {
        $mail = $this->mailConfig();
        $host = (string) $mail['host'];
        $port = (int) ($mail['port'] ?? 587);
        $encryption = (string) ($mail['encryption'] ?? 'tls');
        $username = (string) ($mail['username'] ?? '');
        $password = (string) ($mail['password'] ?? '');
        $fromAddress = (string) $mail['from_address'];
        $fromName = (string) ($mail['from_name'] ?? 'MizaPos');
        $replyTo = trim((string) ($mail['reply_to'] ?? $fromAddress));

        $socket = @fsockopen($host, $port, $errno, $errstr, 20);
        if ($socket === false) {
            throw new RuntimeException("SMTP connect failed: {$errstr} ({$errno})");
        }

        stream_set_timeout($socket, 20);

        try {
            $this->expect($socket, [220]);
            $this->command($socket, 'EHLO mizapos.local', [250]);

            if ($encryption === 'tls') {
                $this->command($socket, 'STARTTLS', [220]);
                if (!stream_socket_enable_crypto($socket, true, STREAM_CRYPTO_METHOD_TLS_CLIENT)) {
                    throw new RuntimeException('SMTP STARTTLS failed');
                }
                $this->command($socket, 'EHLO mizapos.local', [250]);
            }

            if ($username !== '' && $password !== '') {
                $this->command($socket, 'AUTH LOGIN', [334]);
                $this->command($socket, base64_encode($username), [334]);
                $this->command($socket, base64_encode($password), [235]);
            }

            $fromHeader = $this->encodeAddress($fromAddress, $fromName);
            $this->command($socket, "MAIL FROM:<{$fromAddress}>", [250]);
            $this->command($socket, "RCPT TO:<{$to}>", [250, 251]);
            $this->command($socket, 'DATA', [354]);

            $boundary = 'miza_' . bin2hex(random_bytes(8));
            $headers = [
                "From: {$fromHeader}",
                "To: {$to}",
                "Reply-To: {$replyTo}",
                'MIME-Version: 1.0',
                'Date: ' . gmdate('D, d M Y H:i:s') . ' +0000',
                'Subject: ' . $this->encodeHeader($subject),
            ];

            if ($htmlBody !== null && $htmlBody !== '') {
                $headers[] = "Content-Type: multipart/alternative; boundary=\"{$boundary}\"";
                $body = "--{$boundary}\r\n"
                    . "Content-Type: text/plain; charset=UTF-8\r\n"
                    . "Content-Transfer-Encoding: 8bit\r\n\r\n"
                    . $this->normalizeBody($textBody) . "\r\n"
                    . "--{$boundary}\r\n"
                    . "Content-Type: text/html; charset=UTF-8\r\n"
                    . "Content-Transfer-Encoding: 8bit\r\n\r\n"
                    . $this->normalizeBody($htmlBody) . "\r\n"
                    . "--{$boundary}--";
            } else {
                $headers[] = 'Content-Type: text/plain; charset=UTF-8';
                $headers[] = 'Content-Transfer-Encoding: 8bit';
                $body = $this->normalizeBody($textBody);
            }

            $message = implode("\r\n", $headers) . "\r\n\r\n" . $body . "\r\n.";
            fwrite($socket, $message . "\r\n");
            $this->expect($socket, [250]);
            $this->command($socket, 'QUIT', [221]);
        } finally {
            fclose($socket);
        }
    }

    /** @param resource $socket */
    private function command($socket, string $command, array $expectedCodes): void
    {
        fwrite($socket, $command . "\r\n");
        $this->expect($socket, $expectedCodes);
    }

    /** @param resource $socket */
    private function expect($socket, array $expectedCodes): void
    {
        $response = '';
        while (($line = fgets($socket, 515)) !== false) {
            $response .= $line;
            if (isset($line[3]) && $line[3] === ' ') {
                break;
            }
        }

        if ($response === '') {
            throw new RuntimeException('SMTP empty response');
        }

        $code = (int) substr($response, 0, 3);
        if (!in_array($code, $expectedCodes, true)) {
            throw new RuntimeException('SMTP error: ' . trim($response));
        }
    }

    private function encodeAddress(string $email, string $name): string
    {
        $name = trim($name);
        if ($name === '') {
            return $email;
        }

        return $this->encodeHeader($name) . " <{$email}>";
    }

    private function encodeHeader(string $value): string
    {
        if (preg_match('/[^\x20-\x7E]/', $value) === 1) {
            return '=?UTF-8?B?' . base64_encode($value) . '?=';
        }

        return $value;
    }

    private function normalizeBody(string $body): string
    {
        return str_replace(["\r\n", "\r"], "\n", $body);
    }
}
