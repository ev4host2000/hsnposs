<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Support;

use MizaCloud\Modules\Sync\Contract\ChangeDetectionEngine;
use MizaCloud\Modules\Sync\Contract\FieldMetadataProvider;
use MizaCloud\Modules\Sync\Contract\PatchBuilder;
use MizaCloud\Modules\Sync\Contract\PatchValidator;

/**
 * Products golden facade — delegates to shared CatalogPatchOrchestrator.
 * Do not change Products behavior here.
 */
final class ProductPatchOrchestrator
{
    public const ENTITY_TYPE = 'product';

    private readonly CatalogPatchOrchestrator $inner;
    private readonly ProductFullToPatchAdapter $productAdapter;

    public function __construct(
        FieldMetadataProvider $metadata,
        ChangeDetectionEngine $detector,
        PatchBuilder $builder,
        PatchValidator $validator,
        ProductFullToPatchAdapter $adapter,
    ) {
        $this->productAdapter = $adapter;
        $this->inner = new CatalogPatchOrchestrator(
            $metadata,
            $detector,
            $builder,
            $validator,
            // Reuse same engines; Product adapter wraps Catalog adapter.
            new CatalogFullToPatchAdapter($detector, $builder, $metadata),
        );
    }

    public function metadata(): FieldMetadataProvider
    {
        return $this->inner->metadata();
    }

    public function detector(): ChangeDetectionEngine
    {
        return $this->inner->detector();
    }

    public function builder(): PatchBuilder
    {
        return $this->inner->builder();
    }

    public function validator(): PatchValidator
    {
        return $this->inner->validator();
    }

    public function adapter(): ProductFullToPatchAdapter
    {
        return $this->productAdapter;
    }

    /**
     * @param array<string, mixed> $event
     * @param array<string, mixed> $payloadJson
     * @param array<string, mixed> $serverRow
     * @return array{
     *   decision: string,
     *   patch: array<string, mixed>,
     *   normalized_changed_fields: array<string, mixed>,
     *   new_row_version: int,
     *   errors: list<string>,
     *   source: 'native_patch'|'full_to_patch_adapter'
     * }
     */
    public function planUpdate(
        string $entityId,
        string $operation,
        array $event,
        array $payloadJson,
        array $serverRow,
        int $clientRowVersion,
    ): array {
        return $this->inner->planUpdate(
            self::ENTITY_TYPE,
            PatchValidator::PATH_PRODUCT_CATALOG_PATCH,
            $entityId,
            $operation,
            $event,
            $payloadJson,
            $serverRow,
            $clientRowVersion,
        );
    }
}
