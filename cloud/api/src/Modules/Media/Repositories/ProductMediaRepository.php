<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Media\Repositories;

use MizaCloud\Core\Database\Repository;
use PDO;

final class ProductMediaRepository extends Repository
{
    public function findProductScope(string $productId, string $companyId): ?array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT id, company_id, branch_id, image_url
             FROM products
             WHERE id = :id AND company_id = :company_id AND deleted_at IS NULL
             LIMIT 1',
        );
        $stmt->execute([
            'id' => $productId,
            'company_id' => $companyId,
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    public function updateImageUrl(string $productId, string $companyId, ?string $imageUrl): void
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE products
             SET image_url = :image_url, updated_at = now()
             WHERE id = :id AND company_id = :company_id',
        );
        $stmt->execute([
            'image_url' => $imageUrl,
            'id' => $productId,
            'company_id' => $companyId,
        ]);
    }
}
