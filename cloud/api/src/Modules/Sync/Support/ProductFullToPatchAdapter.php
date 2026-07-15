<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Support;

use MizaCloud\Modules\Sync\Contract\ChangeDetectionEngine;
use MizaCloud\Modules\Sync\Contract\FieldMetadataProvider;
use MizaCloud\Modules\Sync\Contract\PatchBuilder;

/**
 * Products golden facade — delegates to shared CatalogFullToPatchAdapter.
 * Do not change Products behavior here.
 */
final class ProductFullToPatchAdapter
{
    public const ENTITY_TYPE = 'product';

    private readonly CatalogFullToPatchAdapter $inner;

    public function __construct(
        ChangeDetectionEngine $detector,
        PatchBuilder $builder,
        FieldMetadataProvider $metadata,
    ) {
        $this->inner = new CatalogFullToPatchAdapter($detector, $builder, $metadata);
    }

    /**
     * @param array<string, mixed> $serverRow
     * @param array<string, mixed> $fullPayload
     * @return array<string, mixed>
     */
    public function adapt(
        string $entityId,
        array $serverRow,
        array $fullPayload,
        string $operationId,
        ?int $baseRowVersion = null,
    ): array {
        return $this->inner->adapt(
            self::ENTITY_TYPE,
            $entityId,
            $serverRow,
            $fullPayload,
            $operationId,
            $baseRowVersion,
        );
    }

    /**
     * @param array<string, mixed> $serverRow
     * @return array<string, mixed>
     */
    public function snapshotFromServerRow(array $serverRow): array
    {
        return $this->inner->snapshotFromServerRow(self::ENTITY_TYPE, $serverRow);
    }

    /**
     * @param array<string, mixed> $fullPayload
     * @param array<string, mixed> $baseSnapshot
     * @return array<string, mixed>
     */
    public function snapshotFromFullPayload(array $fullPayload, array $baseSnapshot): array
    {
        return $this->inner->snapshotFromFullPayload(self::ENTITY_TYPE, $fullPayload, $baseSnapshot);
    }

    /**
     * @param array<string, mixed> $event
     * @param array<string, mixed> $payloadJson
     */
    public static function isNativePatchEvent(string $operation, array $event, array $payloadJson): bool
    {
        return CatalogFullToPatchAdapter::isNativePatchEvent($operation, $event, $payloadJson);
    }
}
