<?php

declare(strict_types=1);

namespace MizaCloud\Core\Database;

use PDO;
use PDOException;

/**
 * اتصال PostgreSQL — بدون استعلامات أو migrations.
 */
final class Connection
{
    private ?PDO $pdo = null;

    /** @param array<string, mixed> $config */
    public function __construct(private readonly array $config) {}

    public function pdo(): PDO
    {
        if ($this->pdo instanceof PDO) {
            return $this->pdo;
        }

        $host = (string) ($this->config['host'] ?? '127.0.0.1');
        $port = (int) ($this->config['port'] ?? 5432);
        $db = (string) ($this->config['database'] ?? '');
        $user = (string) ($this->config['username'] ?? '');
        $pass = (string) ($this->config['password'] ?? '');

        $dsn = "pgsql:host={$host};port={$port};dbname={$db}";

        try {
            $this->pdo = new PDO($dsn, $user, $pass, [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            ]);
        } catch (PDOException $e) {
            throw $e;
        }

        return $this->pdo;
    }

    public function disconnect(): void
    {
        $this->pdo = null;
    }
}
