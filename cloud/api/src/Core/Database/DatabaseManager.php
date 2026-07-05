<?php

declare(strict_types=1);

namespace MizaCloud\Core\Database;

/**
 * مدير اتصال DB — يوفّر Connection للـ Repositories.
 */
final class DatabaseManager
{
    public function __construct(private readonly Connection $connection) {}

    public function connection(): Connection
    {
        return $this->connection;
    }

    public function ping(): bool
    {
        try {
            $this->connection->pdo()->query('SELECT 1');
            return true;
        } catch (\Throwable) {
            return false;
        }
    }
}
