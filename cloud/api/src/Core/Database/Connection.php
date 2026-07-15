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

    public function createSavepoint(string $name): void
    {
        $this->pdo()->exec('SAVEPOINT ' . $this->assertSavepointName($name));
    }

    public function rollbackToSavepoint(string $name): void
    {
        $this->pdo()->exec('ROLLBACK TO SAVEPOINT ' . $this->assertSavepointName($name));
    }

    public function releaseSavepoint(string $name): void
    {
        $this->pdo()->exec('RELEASE SAVEPOINT ' . $this->assertSavepointName($name));
    }

    private function assertSavepointName(string $name): string
    {
        if (!preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/', $name)) {
            throw new \InvalidArgumentException('Invalid savepoint name');
        }

        return $name;
    }
}
