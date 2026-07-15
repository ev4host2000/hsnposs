<?php

declare(strict_types=1);

/**
 * Phase A unit tests — Field Dictionary / Change Detection / Patch (pure logic).
 *
 * Run: php cloud/api/src/Modules/Sync/test_phase_a_contract_unit.php
 */

spl_autoload_register(static function (string $class): void {
    $prefix = 'MizaCloud\\';
    if (!str_starts_with($class, $prefix)) {
        return;
    }
    $rel = str_replace('\\', '/', substr($class, strlen($prefix)));
    $path = dirname(__DIR__, 3) . '/src/' . $rel . '.php';
    if (is_file($path)) {
        require_once $path;
    }
});

use MizaCloud\Modules\Sync\Contract\ChangeDetectionEngine;
use MizaCloud\Modules\Sync\Contract\EntitySpec;
use MizaCloud\Modules\Sync\Contract\FieldDictionary;
use MizaCloud\Modules\Sync\Contract\FieldDictionaryLoader;
use MizaCloud\Modules\Sync\Contract\FieldMetadataProvider;
use MizaCloud\Modules\Sync\Contract\FieldSpec;
use MizaCloud\Modules\Sync\Contract\PatchBuilder;
use MizaCloud\Modules\Sync\Contract\PatchValidator;

$failed = 0;
$passed = 0;

function assertSame(mixed $expected, mixed $actual, string $msg): void
{
    global $failed, $passed;
    if ($expected !== $actual) {
        ++$failed;
        fwrite(STDERR, "FAIL: {$msg}\n  expected: " . var_export($expected, true)
            . "\n  actual:   " . var_export($actual, true) . "\n");
        return;
    }
    ++$passed;
    echo "OK: {$msg}\n";
}

function assertTrue(bool $cond, string $msg): void
{
    assertSame(true, $cond, $msg);
}

function assertFalse(bool $cond, string $msg): void
{
    assertSame(false, $cond, $msg);
}

function expectException(callable $fn, string $msgContains, string $msg): void
{
    global $failed, $passed;
    try {
        $fn();
        ++$failed;
        fwrite(STDERR, "FAIL: {$msg}\n  expected exception containing: {$msgContains}\n");
    } catch (\Throwable $e) {
        if (!str_contains($e->getMessage(), $msgContains)) {
            ++$failed;
            fwrite(STDERR, "FAIL: {$msg}\n  expected message containing: {$msgContains}\n  got: {$e->getMessage()}\n");
            return;
        }
        ++$passed;
        echo "OK: {$msg}\n";
    }
}

function fixtureDictionary(): FieldDictionary
{
    return FieldDictionaryLoader::fromArray([
        'dictionary_version' => '1.0.0-test',
        'entities' => [
            'product' => [
                'entity_type' => 'product',
                'fields' => [
                    [
                        'name' => 'name',
                        'type' => 'string',
                        'nullable' => false,
                        'comparison_rule' => 'string_default',
                        'patchable' => true,
                        'syncable' => true,
                    ],
                    [
                        'name' => 'sale_price',
                        'type' => 'decimal',
                        'nullable' => false,
                        'decimal_scale' => 4,
                        'comparison_rule' => 'decimal_scale',
                        'patchable' => true,
                        'syncable' => true,
                    ],
                    [
                        'name' => 'barcode',
                        'type' => 'string',
                        'nullable' => true,
                        'comparison_rule' => 'string_default',
                        'patchable' => true,
                        'syncable' => true,
                        'empty_as_null' => false,
                    ],
                    [
                        'name' => 'category_id',
                        'type' => 'uuid',
                        'nullable' => true,
                        'comparison_rule' => 'uuid_canonical',
                        'patchable' => true,
                        'syncable' => true,
                    ],
                    [
                        'name' => 'image_url',
                        'type' => 'image_url',
                        'nullable' => true,
                        'comparison_rule' => 'image_url_special',
                        'patchable' => true,
                        'syncable' => true,
                        'empty_as_null' => true,
                    ],
                    [
                        'name' => 'is_hidden',
                        'type' => 'boolean',
                        'nullable' => false,
                        'default_value' => false,
                        'comparison_rule' => 'boolean_default',
                        'patchable' => true,
                        'syncable' => true,
                    ],
                    [
                        'name' => 'sort_order',
                        'type' => 'integer',
                        'nullable' => false,
                        'default_value' => 0,
                        'comparison_rule' => 'integer_default',
                        'patchable' => true,
                        'syncable' => true,
                    ],
                    [
                        'name' => 'updated_at',
                        'type' => 'datetime',
                        'nullable' => true,
                        'comparison_rule' => 'datetime_iso8601',
                        'patchable' => true,
                        'syncable' => true,
                    ],
                    [
                        'name' => 'legacy_code',
                        'type' => 'string',
                        'nullable' => true,
                        'comparison_rule' => 'string_default',
                        'patchable' => true,
                        'syncable' => false,
                        'deprecated' => true,
                    ],
                    [
                        'name' => 'stock_qty',
                        'type' => 'decimal',
                        'nullable' => false,
                        'decimal_scale' => 4,
                        'default_value' => 0,
                        'comparison_rule' => 'decimal_scale',
                        'patchable' => false,
                        'syncable' => false,
                        'forbidden_on_entity_paths' => ['product_catalog_patch'],
                    ],
                    [
                        'name' => 'internal_note',
                        'type' => 'string',
                        'nullable' => true,
                        'comparison_rule' => 'string_default',
                        'patchable' => true,
                        'syncable' => true,
                        'searchable' => true,
                        'sortable' => false,
                        'localized' => false,
                        'security_level' => 'manager',
                    ],
                ],
            ],
        ],
    ]);
}

function stack(): array
{
    $dict = fixtureDictionary();
    $meta = new FieldMetadataProvider($dict);
    $engine = new ChangeDetectionEngine($meta);
    $builder = new PatchBuilder($engine, $meta);
    $validator = new PatchValidator($meta, $engine);

    return compact('dict', 'meta', 'engine', 'builder', 'validator');
}

echo "=== Phase A Contract unit tests ===\n\n";

// ---------------------------------------------------------------------------
// FieldSpec / EntitySpec / FieldDictionary
// ---------------------------------------------------------------------------
echo "-- FieldSpec / EntitySpec / FieldDictionary --\n";

$fs = FieldSpec::fromArray([
    'name' => 'n',
    'type' => 'string',
    'nullable' => true,
    'comparison_rule' => 'string_default',
    'patchable' => true,
    'syncable' => true,
    'decimal_scale' => '2',
    'forbidden_on_entity_paths' => ['x'],
]);
assertSame('n', $fs->name, 'FieldSpec name');
assertSame(2, $fs->decimalScale, 'FieldSpec decimal_scale from numeric string');
assertSame(['x'], $fs->forbiddenOnEntityPaths, 'FieldSpec forbidden paths');
assertTrue(is_array($fs->toArray()), 'FieldSpec toArray');

expectException(
    static fn () => FieldSpec::fromArray(['type' => 'string', 'comparison_rule' => 'string_default']),
    'name',
    'FieldSpec rejects missing name'
);
expectException(
    static fn () => FieldSpec::fromArray(['name' => 'a', 'comparison_rule' => 'string_default']),
    'type',
    'FieldSpec rejects missing type'
);
expectException(
    static fn () => FieldSpec::fromArray(['name' => 'a', 'type' => 'string']),
    'comparison_rule',
    'FieldSpec rejects missing comparison_rule'
);
expectException(
    static fn () => FieldSpec::fromArray([
        'name' => 'a', 'type' => 'decimal', 'comparison_rule' => 'decimal_scale',
        'decimal_scale' => 'x',
    ]),
    'decimal_scale',
    'FieldSpec rejects bad decimal_scale'
);
expectException(
    static fn () => FieldSpec::fromArray([
        'name' => 'a', 'type' => 'decimal', 'comparison_rule' => 'decimal_scale',
        'decimal_scale' => -1,
    ]),
    'decimal_scale',
    'FieldSpec rejects negative decimal_scale'
);
expectException(
    static fn () => FieldSpec::fromArray([
        'name' => 'a', 'type' => 'string', 'comparison_rule' => 'string_default',
        'forbidden_on_entity_paths' => [''],
    ]),
    'forbidden_on_entity_paths',
    'FieldSpec rejects empty forbidden path'
);

expectException(
    static fn () => new EntitySpec('', []),
    'entity_type',
    'EntitySpec rejects empty type'
);
expectException(
    static fn () => EntitySpec::fromArray(['fields' => []]),
    'entity_type',
    'EntitySpec fromArray requires entity_type'
);
expectException(
    static fn () => EntitySpec::fromArray(['entity_type' => 'x']),
    'fields',
    'EntitySpec fromArray requires fields'
);
expectException(
    static fn () => EntitySpec::fromArray(['entity_type' => 'x', 'fields' => ['bad']]),
    'object',
    'EntitySpec rejects non-array field'
);
expectException(
    static fn () => EntitySpec::fromArray([
        'entity_type' => 'x',
        'fields' => [
            ['name' => 'a', 'type' => 'string', 'comparison_rule' => 'string_default'],
            ['name' => 'a', 'type' => 'string', 'comparison_rule' => 'string_default'],
        ],
    ]),
    'Duplicate',
    'EntitySpec rejects duplicate field'
);

$es = EntitySpec::fromArray([
    'entity_type' => 'demo',
    'fields' => [
        ['name' => 'a', 'type' => 'string', 'comparison_rule' => 'string_default', 'patchable' => true],
        ['name' => 'b', 'type' => 'string', 'comparison_rule' => 'string_default', 'patchable' => false],
        ['name' => 'c', 'type' => 'string', 'comparison_rule' => 'string_default', 'patchable' => true, 'deprecated' => true],
    ],
]);
assertTrue($es->hasField('a'), 'EntitySpec hasField true');
assertFalse($es->hasField('z'), 'EntitySpec hasField false');
assertSame('a', $es->field('a')->name, 'EntitySpec field()');
expectException(static fn () => $es->field('z'), 'Unknown field', 'EntitySpec field unknown');
assertSame(1, count($es->patchableFields()), 'EntitySpec patchable excludes non-patchable+deprecated');

expectException(static fn () => new FieldDictionary('', []), 'dictionary_version', 'FieldDictionary rejects empty version');
$fd = new FieldDictionary('1.0.0', ['demo' => $es]);
assertTrue($fd->hasEntity('demo'), 'FieldDictionary hasEntity');
assertFalse($fd->hasEntity('nope'), 'FieldDictionary missing entity');
assertSame(['demo'], $fd->entityTypes(), 'FieldDictionary entityTypes');
expectException(static fn () => $fd->entity('nope'), 'Unknown entity_type', 'FieldDictionary entity unknown');

// ---------------------------------------------------------------------------
// FieldDictionaryLoader
// ---------------------------------------------------------------------------
echo "\n-- FieldDictionaryLoader --\n";

expectException(static fn () => new FieldDictionaryLoader(''), 'dictionaryRoot', 'Loader rejects empty root');

$root = dirname(__DIR__, 3) . '/contracts/field-dictionary';
$loader = new FieldDictionaryLoader($root);
$loaded = $loader->load('1.0.0');
assertSame('1.0.0', $loaded->dictionaryVersion, 'Loader loads version from disk');
assertTrue($loaded->hasEntity('product'), 'Loader loads product entity');
assertTrue($loaded->entity('product')->hasField('sale_price'), 'Loader product has sale_price');
assertFalse($loaded->entity('product')->field('stock_qty')->patchable, 'stock_qty not patchable in dict');

expectException(static fn () => $loader->load(''), 'version', 'Loader rejects empty version');
expectException(static fn () => $loader->load('9.9.9'), 'not found', 'Loader missing version');

expectException(
    static fn () => FieldDictionaryLoader::fromArray(['entities' => []]),
    'dictionary_version',
    'fromArray requires version'
);
expectException(
    static fn () => FieldDictionaryLoader::fromArray(['dictionary_version' => '1']),
    'entities',
    'fromArray requires entities'
);
expectException(
    static fn () => FieldDictionaryLoader::fromArray([
        'dictionary_version' => '1',
        'entities' => ['' => ['entity_type' => 'x', 'fields' => []]],
    ]),
    'entity keys',
    'fromArray rejects empty entity key'
);
expectException(
    static fn () => FieldDictionaryLoader::fromArray([
        'dictionary_version' => '1',
        'entities' => ['x' => 'bad'],
    ]),
    'entity value',
    'fromArray rejects non-array entity'
);
expectException(
    static fn () => FieldDictionaryLoader::fromArray([
        'dictionary_version' => '1',
        'entities' => [
            'product' => ['entity_type' => 'other', 'fields' => []],
        ],
    ]),
    'mismatch',
    'fromArray rejects entity_type key mismatch'
);

$tmp = sys_get_temp_dir() . '/miza_dict_' . bin2hex(random_bytes(4));
mkdir($tmp . '/badver', 0777, true);
file_put_contents($tmp . '/badver/manifest.json', json_encode([
    'dictionary_version' => 'other',
    'entities' => [],
]));
$badLoader = new FieldDictionaryLoader($tmp);
expectException(static fn () => $badLoader->load('badver'), 'does not match', 'Loader version mismatch in manifest');

file_put_contents($tmp . '/badver/manifest.json', 'not-json');
expectException(static fn () => $badLoader->load('badver'), 'Invalid dictionary manifest', 'Loader invalid manifest JSON');

file_put_contents($tmp . '/badver/manifest.json', json_encode([
    'dictionary_version' => 'badver',
]));
expectException(static fn () => $badLoader->load('badver'), 'manifest.entities', 'Loader missing entities');

file_put_contents($tmp . '/badver/manifest.json', json_encode([
    'dictionary_version' => 'badver',
    'entities' => [123],
]));
expectException(static fn () => $badLoader->load('badver'), 'non-empty strings', 'Loader bad entity entry');

file_put_contents($tmp . '/badver/manifest.json', json_encode([
    'dictionary_version' => 'badver',
    'entities' => ['ghost'],
]));
expectException(static fn () => $badLoader->load('badver'), 'Entity dictionary file not found', 'Loader missing entity file');

mkdir($tmp . '/badver/entities', 0777, true);
file_put_contents($tmp . '/badver/entities/ghost.json', 'not-json');
expectException(static fn () => $badLoader->load('badver'), 'Invalid entity dictionary', 'Loader invalid entity JSON');

file_put_contents($tmp . '/badver/entities/ghost.json', json_encode([
    'entity_type' => 'other',
    'fields' => [],
]));
expectException(static fn () => $badLoader->load('badver'), 'entity_type mismatch', 'Loader entity_type file mismatch');

file_put_contents($tmp . '/badver/manifest.json', json_encode([
    'entities' => [],
]));
expectException(static fn () => $badLoader->load('badver'), 'dictionary_version is required', 'Loader manifest missing version');

// ---------------------------------------------------------------------------
// FieldMetadataProvider
// ---------------------------------------------------------------------------
echo "\n-- FieldMetadataProvider --\n";
$s = stack();
/** @var FieldMetadataProvider $meta */
$meta = $s['meta'];
assertSame('1.0.0-test', $meta->dictionaryVersion(), 'Provider version');
assertTrue($meta->hasEntity('product'), 'Provider hasEntity');
assertFalse($meta->hasEntity('partner'), 'Provider missing entity');
assertTrue($meta->hasField('product', 'name'), 'Provider hasField');
assertFalse($meta->hasField('product', 'nope'), 'Provider missing field');
assertFalse($meta->hasField('partner', 'name'), 'Provider hasField on missing entity');
assertTrue($meta->isPatchable('product', 'name'), 'Provider isPatchable name');
assertFalse($meta->isPatchable('product', 'stock_qty'), 'Provider stock_qty not patchable');
assertFalse($meta->isPatchable('product', 'legacy_code'), 'Provider deprecated not patchable');
assertTrue($meta->isSyncable('product', 'name'), 'Provider isSyncable');
assertFalse($meta->isSyncable('product', 'stock_qty'), 'Provider stock_qty not syncable');
assertTrue(in_array('name', $meta->patchableFieldNames('product'), true), 'Provider patchable names');
assertFalse(in_array('stock_qty', $meta->patchableFieldNames('product'), true), 'Provider excludes stock_qty');
assertTrue($meta->isForbiddenOnPath('product', 'stock_qty', 'product_catalog_patch'), 'Provider forbidden path');
assertFalse($meta->isForbiddenOnPath('product', 'name', 'product_catalog_patch'), 'Provider name not forbidden');
assertSame('product', $meta->entity('product')->entityType, 'Provider entity()');
assertSame('name', $meta->field('product', 'name')->name, 'Provider field()');

// ---------------------------------------------------------------------------
// ChangeDetectionEngine
// ---------------------------------------------------------------------------
echo "\n-- ChangeDetectionEngine --\n";
/** @var ChangeDetectionEngine $engine */
$engine = $s['engine'];

$base = [
    'name' => 'A',
    'sale_price' => '10.0000',
    'barcode' => null,
    'category_id' => 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA',
    'image_url' => null,
    'is_hidden' => false,
    'sort_order' => 1,
    'updated_at' => '2024-01-01T00:00:00Z',
    'stock_qty' => '5.0000',
];
$next = $base;
$next['name'] = 'B';
$next['sale_price'] = 10.0; // same after scale
$next['stock_qty'] = '99.0000'; // not patchable — ignored

$changed = $engine->detect('product', $base, $next);
assertSame(['name' => 'B'], $changed, 'Detect only name; ignore stock_qty and equal decimal');

$next2 = $base;
$next2['sale_price'] = '10.5000';
$next2['is_hidden'] = '1';
$next2['sort_order'] = '2';
$next2['barcode'] = '';
$next2['image_url'] = '  ';
$next2['category_id'] = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
$changed2 = $engine->detect('product', $base, $next2);
assertSame('10.5000', $changed2['sale_price'], 'Detect decimal change');
assertSame(true, $changed2['is_hidden'], 'Detect boolean change from string 1');
assertSame(2, $changed2['sort_order'], 'Detect integer change');
assertSame('', $changed2['barcode'], 'Empty string barcode is change from null');
// image_url '' → null equals base null → should NOT be in changed
assertFalse(array_key_exists('image_url', $changed2), 'image empty_as_null: blank equals null (no change)');
assertSame('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', $changed2['category_id'], 'UUID lowercased');

// missing keys use defaults
$changed3 = $engine->detect('product', [], ['name' => 'X', 'sale_price' => 1]);
assertSame('X', $changed3['name'], 'Detect with defaults on base');
// is_hidden: base default false, next missing → default false → not changed
assertFalse(array_key_exists('is_hidden', $changed3), 'defaults equal → no change for is_hidden');

// normalization unit cases
$nameField = $meta->field('product', 'name');
assertSame('hi', $engine->normalize($nameField, 'hi'), 'normalize string');
expectException(static fn () => $engine->normalize($nameField, true), 'string field', 'normalize string rejects bool');

$dec = $meta->field('product', 'sale_price');
assertSame('1.2500', $engine->normalize($dec, 1.25), 'normalize decimal');
expectException(static fn () => $engine->normalize($dec, true), 'decimal', 'normalize decimal rejects bool');
expectException(static fn () => $engine->normalize($dec, ''), 'decimal', 'normalize decimal rejects empty');
expectException(static fn () => $engine->normalize($dec, 'abc'), 'decimal', 'normalize decimal rejects non-numeric');

$bool = $meta->field('product', 'is_hidden');
assertSame(true, $engine->normalize($bool, true), 'bool true');
assertSame(false, $engine->normalize($bool, 0), 'bool 0');
assertSame(true, $engine->normalize($bool, 'yes'), 'bool yes');
assertSame(false, $engine->normalize($bool, 'no'), 'bool no');
expectException(static fn () => $engine->normalize($bool, 2), 'boolean', 'bool rejects 2');
expectException(static fn () => $engine->normalize($bool, 'maybe'), 'boolean', 'bool rejects maybe');

$int = $meta->field('product', 'sort_order');
assertSame(3, $engine->normalize($int, 3), 'int');
assertSame(3, $engine->normalize($int, 3.0), 'int from float whole');
assertSame(-1, $engine->normalize($int, '-1'), 'int from string');
expectException(static fn () => $engine->normalize($int, 1.5), 'fractional', 'int rejects fractional');
expectException(static fn () => $engine->normalize($int, true), 'integer', 'int rejects bool');
expectException(static fn () => $engine->normalize($int, ''), 'integer', 'int rejects empty');
expectException(static fn () => $engine->normalize($int, '1.0'), 'integer', 'int rejects decimal string');

$uuid = $meta->field('product', 'category_id');
assertSame(null, $engine->normalize($uuid, null), 'uuid null');
assertSame(null, $engine->normalize($uuid, '  '), 'uuid blank → null');
assertSame('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $engine->normalize($uuid, 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'), 'uuid canonical');
expectException(static fn () => $engine->normalize($uuid, 1), 'uuid', 'uuid rejects int');
expectException(static fn () => $engine->normalize($uuid, 'not-a-uuid'), 'uuid', 'uuid rejects bad format');

$dt = $meta->field('product', 'updated_at');
assertSame(null, $engine->normalize($dt, null), 'datetime null');
assertTrue(str_ends_with((string) $engine->normalize($dt, '2024-06-01 12:00:00 UTC'), 'Z'), 'datetime to Z');
expectException(static fn () => $engine->normalize($dt, ''), 'datetime', 'datetime rejects empty');
expectException(static fn () => $engine->normalize($dt, 'not-a-date'), 'datetime', 'datetime rejects garbage');

$img = $meta->field('product', 'image_url');
assertSame(null, $engine->normalize($img, '   '), 'image blank → null');
assertSame('https://x/y.png', $engine->normalize($img, 'https://x/y.png'), 'image url');
expectException(static fn () => $engine->normalize($img, 1), 'image_url', 'image rejects non-string');

// unsupported comparison rule
$badField = new FieldSpec(
    name: 'x',
    type: 'string',
    nullable: true,
    defaultValue: null,
    comparisonRule: 'unknown_rule',
    securityLevel: 'staff',
    patchable: true,
    syncable: true,
    searchable: false,
    sortable: false,
    localized: false,
    deprecated: false,
);
expectException(static fn () => $engine->normalize($badField, 'a'), 'Unsupported comparison_rule', 'unknown rule');

assertTrue($engine->valuesEqual($dec, '1.0000', '1.0000'), 'valuesEqual decimal');
assertFalse($engine->valuesEqual($dec, '1.0000', '2.0000'), 'valuesEqual decimal diff');
assertTrue($engine->valuesEqual($bool, true, true), 'valuesEqual bool');
assertTrue($engine->valuesEqual($int, 1, 1), 'valuesEqual int');
assertFalse($engine->valuesEqual($nameField, null, 'a'), 'valuesEqual null vs value');
assertTrue($engine->valuesEqual($nameField, null, null), 'valuesEqual both null');

// non-nullable with default when null
assertSame(false, $engine->normalize($bool, null), 'null bool uses default false');

// ---------------------------------------------------------------------------
// PatchBuilder
// ---------------------------------------------------------------------------
echo "\n-- PatchBuilder --\n";
/** @var PatchBuilder $builder */
$builder = $s['builder'];

$patch = $builder->buildUpdatePatch(
    'product',
    'ent-1',
    'op-1',
    3,
    ['name' => 'A', 'sale_price' => 1],
    ['name' => 'B', 'sale_price' => 1],
);
assertSame('update', $patch['operation'], 'Builder operation');
assertSame('B', $patch['changed_fields']['name'], 'Builder changed name');
assertFalse($patch['is_no_op'], 'Builder not no_op');
assertSame('1.0.0-test', $patch['dictionary_version'], 'Builder dict version');

$noop = $builder->buildUpdatePatch(
    'product',
    'ent-1',
    'op-2',
    3,
    ['name' => 'A', 'sale_price' => '1.0000', 'is_hidden' => false, 'sort_order' => 0],
    ['name' => 'A', 'sale_price' => 1, 'is_hidden' => 0, 'sort_order' => '0'],
);
assertTrue($noop['is_no_op'], 'Builder no_op when equal after normalize');
assertSame([], $noop['changed_fields'], 'Builder empty changed_fields');

$fromMap = $builder->buildFromChangedFields('product', 'ent-1', 'op-3', 2, ['sale_price' => 9.5]);
assertSame('9.5000', $fromMap['changed_fields']['sale_price'], 'Builder from map normalizes');

expectException(static fn () => $builder->buildUpdatePatch('', 'e', 'o', 1, [], []), 'entity_type', 'Builder empty entity');
expectException(static fn () => $builder->buildUpdatePatch('product', '', 'o', 1, [], []), 'entity_id', 'Builder empty id');
expectException(static fn () => $builder->buildUpdatePatch('product', 'e', '', 1, [], []), 'operation_id', 'Builder empty op id');
expectException(static fn () => $builder->buildUpdatePatch('product', 'e', 'o', 0, [], []), 'base_row_version', 'Builder bad version');
expectException(static fn () => $builder->buildUpdatePatch('partner', 'e', 'o', 1, [], []), 'Unknown entity_type', 'Builder unknown entity');

expectException(static fn () => $builder->buildFromChangedFields('', 'e', 'o', 1, []), 'entity_type', 'fromMap empty entity');
expectException(static fn () => $builder->buildFromChangedFields('product', '', 'o', 1, []), 'entity_id', 'fromMap empty id');
expectException(static fn () => $builder->buildFromChangedFields('product', 'e', '', 1, []), 'operation_id', 'fromMap empty op');
expectException(static fn () => $builder->buildFromChangedFields('product', 'e', 'o', 0, []), 'base_row_version', 'fromMap bad ver');
expectException(static fn () => $builder->buildFromChangedFields('partner', 'e', 'o', 1, []), 'Unknown entity_type', 'fromMap unknown');
expectException(
    static fn () => $builder->buildFromChangedFields('product', 'e', 'o', 1, ['' => 1]),
    'changed_fields keys',
    'fromMap empty key'
);
expectException(
    static fn () => $builder->buildFromChangedFields('product', 'e', 'o', 1, ['stock_qty' => 1]),
    'not patchable',
    'fromMap rejects stock_qty'
);

// ---------------------------------------------------------------------------
// PatchValidator
// ---------------------------------------------------------------------------
echo "\n-- PatchValidator --\n";
/** @var PatchValidator $validator */
$validator = $s['validator'];

$validPatch = [
    'entity_type' => 'product',
    'entity_id' => 'ent-1',
    'operation' => 'update',
    'operation_id' => 'op-9',
    'base_row_version' => 4,
    'dictionary_version' => '1.0.0-test',
    'changed_fields' => ['name' => 'Z', 'sale_price' => 2],
];
$vr = $validator->validate($validPatch);
assertSame(PatchValidator::RESULT_VALID, $vr['status'], 'Validator accepts good patch');
assertSame([], $vr['errors'], 'Validator no errors');
assertSame('2.0000', $vr['normalized_changed_fields']['sale_price'], 'Validator normalizes');
assertTrue($validator->isValid($validPatch), 'isValid true');

$bad = $validator->validate([]);
assertSame(PatchValidator::RESULT_INVALID, $bad['status'], 'Validator empty invalid');
assertTrue(count($bad['errors']) >= 5, 'Validator reports multiple required errors');
assertFalse($validator->isValid([]), 'isValid false');

$r = $validator->validate(array_merge($validPatch, ['dictionary_version' => '9.9.9']));
assertTrue(str_contains(implode(';', $r['errors']), 'dictionary_version mismatch'), 'dict mismatch');

$r = $validator->validate(array_merge($validPatch, ['entity_type' => 'partner']));
assertTrue(str_contains(implode(';', $r['errors']), 'Unknown entity_type'), 'unknown entity');

$r = $validator->validate(array_merge($validPatch, ['changed_fields' => ['stock_qty' => '1']]));
assertTrue(str_contains(implode(';', $r['errors']), 'not patchable'), 'rejects stock_qty patchable');

$r = $validator->validate(array_merge($validPatch, ['changed_fields' => ['nope' => 1]]));
assertTrue(str_contains(implode(';', $r['errors']), 'Unknown field'), 'unknown field');

$r = $validator->validate(array_merge($validPatch, ['changed_fields' => ['legacy_code' => 'x']]));
assertTrue(str_contains(implode(';', $r['errors']), 'Deprecated'), 'deprecated field');

$r = $validator->validate(array_merge($validPatch, ['changed_fields' => ['name' => null]]));
assertTrue(str_contains(implode(';', $r['errors']), 'does not allow null'), 'non-null name');

$r = $validator->validate(array_merge($validPatch, ['changed_fields' => ['sale_price' => 'abc']]));
assertTrue(str_contains(implode(';', $r['errors']), 'Invalid value'), 'bad decimal value');

$r = $validator->validate(array_merge($validPatch, ['operation' => 'create']));
assertTrue(str_contains(implode(';', $r['errors']), 'operation must be'), 'operation must update');

$r = $validator->validate(array_merge($validPatch, ['base_row_version' => 0]));
assertTrue(str_contains(implode(';', $r['errors']), 'base_row_version must be >= 1'), 'version >= 1');

$r = $validator->validate(array_merge($validPatch, ['base_row_version' => 'x']));
assertTrue(str_contains(implode(';', $r['errors']), 'base_row_version must be a positive integer'), 'version type');

$r = $validator->validate(array_merge($validPatch, ['changed_fields' => 'x']));
assertTrue(str_contains(implode(';', $r['errors']), 'changed_fields must be'), 'changed_fields type');

$r = $validator->validate(array_merge($validPatch, ['changed_fields' => ['' => 1]]));
assertTrue(str_contains(implode(';', $r['errors']), 'changed_fields keys'), 'empty key');

// forbidden path even if somehow patchable — stock already not patchable; add path check via explicit path
// Use a field that is patchable but forbidden on path: only stock_qty in dict — already caught as not patchable.
// Cover path branch by validating with entityPath when field has forbidden path — stock fails earlier on patchable.
// Ensure path check runs for patchable+forbidden: temporarily validate via custom field in fixture — already have stock_qty not patchable.
// Force path: create mini stack with patchable+forbidden field.
$pathDict = FieldDictionaryLoader::fromArray([
    'dictionary_version' => 'path-test',
    'entities' => [
        'product' => [
            'entity_type' => 'product',
            'fields' => [
                [
                    'name' => 'secret',
                    'type' => 'string',
                    'nullable' => true,
                    'comparison_rule' => 'string_default',
                    'patchable' => true,
                    'syncable' => true,
                    'forbidden_on_entity_paths' => ['product_catalog_patch'],
                ],
            ],
        ],
    ],
]);
$pathMeta = new FieldMetadataProvider($pathDict);
$pathEngine = new ChangeDetectionEngine($pathMeta);
$pathValidator = new PatchValidator($pathMeta, $pathEngine);
$r = $pathValidator->validate([
    'entity_type' => 'product',
    'entity_id' => 'e',
    'operation' => 'update',
    'operation_id' => 'o',
    'base_row_version' => 1,
    'dictionary_version' => 'path-test',
    'changed_fields' => ['secret' => 'x'],
], PatchValidator::PATH_PRODUCT_CATALOG_PATCH);
assertTrue(str_contains(implode(';', $r['errors']), 'forbidden on path'), 'forbidden on entity path');

// string base_row_version digit accepted
$r = $validator->validate(array_merge($validPatch, ['base_row_version' => '5']));
assertSame(PatchValidator::RESULT_VALID, $r['status'], 'string digit base_row_version accepted');

// cleanup temp
@unlink($tmp . '/badver/entities/ghost.json');
@rmdir($tmp . '/badver/entities');
@unlink($tmp . '/badver/manifest.json');
@rmdir($tmp . '/badver');
@rmdir($tmp);

echo "\n=== Results: {$passed} passed, {$failed} failed ===\n";
exit($failed > 0 ? 1 : 0);
