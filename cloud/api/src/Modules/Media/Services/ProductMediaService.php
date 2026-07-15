<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Media\Services;

use MizaCloud\Core\Config\Config;
use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Modules\Devices\Support\BearerToken;
use MizaCloud\Modules\Media\Repositories\ProductMediaRepository;

final class ProductMediaService
{
    private const MAX_BYTES = 2_097_152;

    /** @var array<string, string> */
    private const MIME_TO_EXT = [
        'image/jpeg' => 'jpg',
        'image/jpg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
    ];

    public function __construct(
        private readonly ProductMediaRepository $repository,
        private readonly BearerToken $bearer,
        private readonly Config $config,
        private readonly Logger $logger,
        private readonly string $storageRoot,
    ) {}

    /** @return array<string, mixed> */
    public function uploadProductImage(Request $request): array
    {
        $claims = $this->bearer->authenticate($request, ['sync:push']);
        $productId = trim((string) $request->attribute('productId', ''));
        $companyId = (string) ($claims['company_id'] ?? '');

        if ($productId === '' || $companyId === '') {
            throw new HttpException('validation_error', 'Product and company context required', 400);
        }

        if (($claims['company_id'] ?? '') !== $companyId) {
            throw new HttpException('forbidden', 'Company mismatch', 403);
        }

        $product = $this->repository->findProductScope($productId, $companyId);
        if ($product === null) {
            throw new HttpException('not_found', 'Product not found', 404);
        }

        $upload = $this->resolveUploadedFile($request);
        $ext = $this->detectExtension($upload);
        $targetDir = $this->storageRoot . '/' . $companyId;
        if (!is_dir($targetDir) && !mkdir($targetDir, 0755, true) && !is_dir($targetDir)) {
            throw new HttpException('internal_error', 'Failed to create media directory', 500);
        }

        $filename = $productId . '.' . $ext;
        $absolutePath = $targetDir . '/' . $filename;
        if (!move_uploaded_file($upload['tmp_name'], $absolutePath)) {
            throw new HttpException('internal_error', 'Failed to store uploaded image', 500);
        }

        $imageUrl = rtrim($this->publicBaseUrl(), '/') . '/media/' . $companyId . '/' . $filename;
        $this->repository->updateImageUrl($productId, $companyId, $imageUrl);

        $this->logger->info('media.product_image.uploaded', [
            'company_id' => $companyId,
            'product_id' => $productId,
            'bytes' => $upload['size'],
        ]);

        return [
            'product_id' => $productId,
            'company_id' => $companyId,
            'image_url' => $imageUrl,
        ];
    }

    /** @return array{name: string, tmp_name: string, size: int, error: int, type: string} */
    private function resolveUploadedFile(Request $request): array
    {
        foreach (['image', 'file'] as $field) {
            $candidate = $request->files[$field] ?? null;
            if (is_array($candidate)) {
                return $this->validateUpload($candidate);
            }
        }

        throw new HttpException('validation_error', 'Image file is required (field: image)', 400, [
            'fields' => ['image' => 'Upload an image file'],
        ]);
    }

    /** @param array{name: string, tmp_name: string, size: int, error: int, type: string} $upload */
    private function validateUpload(array $upload): array
    {
        if (($upload['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
            throw new HttpException('validation_error', 'Image upload failed', 400);
        }

        $size = (int) ($upload['size'] ?? 0);
        if ($size <= 0 || $size > self::MAX_BYTES) {
            throw new HttpException('validation_error', 'Image must be <= 2 MB', 400);
        }

        $tmpName = (string) ($upload['tmp_name'] ?? '');
        if ($tmpName === '' || !is_uploaded_file($tmpName)) {
            throw new HttpException('validation_error', 'Invalid upload payload', 400);
        }

        $mime = $this->detectMime($tmpName, (string) ($upload['type'] ?? ''));
        if (!isset(self::MIME_TO_EXT[$mime])) {
            throw new HttpException('validation_error', 'Only JPEG, PNG, or WebP images are allowed', 400);
        }

        $upload['type'] = $mime;

        return $upload;
    }

    /** @param array{name: string, tmp_name: string, size: int, error: int, type: string} $upload */
    private function detectExtension(array $upload): string
    {
        $mime = $this->detectMime((string) $upload['tmp_name'], (string) ($upload['type'] ?? ''));

        return self::MIME_TO_EXT[$mime] ?? 'jpg';
    }

    private function detectMime(string $tmpName, string $declaredType): string
    {
        $finfo = finfo_open(FILEINFO_MIME_TYPE);
        $detected = is_resource($finfo) ? finfo_file($finfo, $tmpName) : false;
        if (is_resource($finfo)) {
            finfo_close($finfo);
        }

        $mime = is_string($detected) && $detected !== '' ? $detected : $declaredType;
        if ($mime === 'application/octet-stream' && $declaredType !== '') {
            $mime = $declaredType;
        }

        return strtolower($mime);
    }

    private function publicBaseUrl(): string
    {
        $app = $this->config->get('app', []);
        if (!is_array($app)) {
            return 'https://api.mizapos.com';
        }

        return (string) ($app['url'] ?? 'https://api.mizapos.com');
    }
}
