# Builds install_all_flat.sql — single file for phpPgAdmin / cPanel SQL import.
# install_all.sql uses \ir which only works in psql CLI.
# Usage: .\build_install_bundle.ps1

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$out = Join-Path $here 'install_all_flat.sql'

$files = @(
    '001_initial_schema.sql',
    '002_indexes.sql',
    '003_constraints.sql',
    '004_seed_data.sql',
    '005_functions.sql',
    '006_triggers.sql',
    '007_views.sql',
    '008_permissions.sql',
    '009_migrations.sql',
    '010_catalog_taxes_price_lists.sql',
    '011_sales_invoice_transaction_version.sql',
    '012_sales_invoice_posted_at.sql',
    '013_purchase_invoice_transaction_version.sql',
    '014_return_transaction_version.sql',
    '015_payment_transaction_version.sql',
    '016_inventory_adjustment_transaction_version.sql',
    '017_opening_stock_transaction_version.sql'
)

$header = @"
-- =============================================================================
-- Miza Cloud — install_all_flat.sql (auto-generated)
-- For phpPgAdmin / cPanel — do NOT use install_all.sql (\ir requires psql CLI)
-- Regenerate: .\build_install_bundle.ps1
-- =============================================================================

"@

Set-Content -Path $out -Value $header -Encoding UTF8

foreach ($f in $files) {
    $path = Join-Path $here $f
    if (-not (Test-Path $path)) {
        throw "Missing migration: $f"
    }
    Add-Content -Path $out -Value "`n-- >>> BEGIN $f`n" -Encoding UTF8
    Get-Content -Path $path -Raw | Add-Content -Path $out -Encoding UTF8
    Add-Content -Path $out -Value "`n-- <<< END $f`n" -Encoding UTF8
}

Write-Host "Created: $out ($((Get-Item $out).Length) bytes)"
