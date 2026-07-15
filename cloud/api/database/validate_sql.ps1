#Requires -Version 5.1
<#
.SYNOPSIS
    Static + optional live validation for cloud/api/database SQL files (001-017).
#>
param(
    [string]$Database = 'mizacloud_validate',
    [string]$PostgresUser = 'postgres',
    [switch]$SkipLive
)

$ErrorActionPreference = 'Stop'
$DbDir = $PSScriptRoot

$CoreFiles = @(
    '001_initial_schema.sql',
    '002_indexes.sql',
    '003_constraints.sql',
    '004_seed_data.sql',
    '005_functions.sql',
    '006_triggers.sql',
    '007_views.sql',
    '008_permissions.sql',
    '009_migrations.sql'
)

$ExtensionFiles = @(
    '010_catalog_taxes_price_lists.sql',
    '011_sales_invoice_transaction_version.sql',
    '012_sales_invoice_posted_at.sql',
    '013_purchase_invoice_transaction_version.sql',
    '014_return_transaction_version.sql',
    '015_payment_transaction_version.sql',
    '016_inventory_adjustment_transaction_version.sql',
    '017_opening_stock_transaction_version.sql'
)

$OrderedFiles = $CoreFiles + $ExtensionFiles

$ExpectedTables = @(
    'companies', 'branches', 'organization_settings', 'branch_settings', 'device_settings',
    'users', 'user_branch_access', 'devices', 'device_sessions', 'api_tokens', 'refresh_tokens',
    'password_reset_tokens', 'email_verification_tokens', 'subscription_plans', 'company_subscriptions',
    'licenses', 'license_device_slots', 'product_categories', 'product_units', 'products',
    'product_sale_units', 'customers', 'suppliers', 'sales_invoices', 'sales_invoice_items',
    'purchase_invoices', 'purchase_invoice_items', 'sales_returns', 'sales_return_items',
    'purchase_returns', 'purchase_return_items', 'invoice_payment_splits', 'stock_movements',
    'partner_ledger', 'cash_transactions', 'expenses', 'cloud_versions', 'sync_changelog',
    'sync_queue', 'sync_conflicts', 'notifications', 'notification_receipts', 'audit_logs'
)

function Test-Check {
    param(
        [bool]$Ok,
        [string]$Message
    )
    if ($Ok) {
        Write-Host "[OK] $Message" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] $Message" -ForegroundColor Red
    }
    return $Ok
}

$allOk = $true

Write-Host ''
Write-Host '=== Miza Cloud SQL - Static Review ===' -ForegroundColor Cyan

foreach ($file in ($OrderedFiles + @('010_cleanup.sql', 'install_all.sql'))) {
    $path = Join-Path $DbDir $file
    $ok = Test-Path $path
    $allOk = (Test-Check $ok ("File exists - " + $file)) -and $allOk
}

foreach ($file in $OrderedFiles) {
    $content = Get-Content (Join-Path $DbDir $file) -Raw
    $hasTxnBegin = $content -match '(?m)^BEGIN\s*;'
    $hasTxnCommit = $content -match '(?m)^COMMIT\s*;'
    $ok = $hasTxnBegin -and $hasTxnCommit
    $msg = "Transaction wrapper in $file"
    $allOk = (Test-Check $ok $msg) -and $allOk
}

# Unique schema_migrations version numbers across 010-017
$versionMap = @{}
foreach ($file in $ExtensionFiles) {
    $content = Get-Content (Join-Path $DbDir $file) -Raw
    if ($content -match "VALUES\s*\(\s*'(\d{3})'") {
        $ver = $Matches[1]
        if ($versionMap.ContainsKey($ver)) {
            $allOk = (Test-Check $false ("Duplicate migration version $ver in " + $file + " and " + $versionMap[$ver])) -and $allOk
        }
        else {
            $versionMap[$ver] = $file
        }
    }
}
$allOk = (Test-Check ($versionMap.Count -eq $ExtensionFiles.Count) ("Unique extension versions 010-017 (" + $versionMap.Count + "/8)")) -and $allOk

$installAll = Get-Content (Join-Path $DbDir 'install_all.sql') -Raw
foreach ($file in $OrderedFiles) {
    $ok = $installAll -match [regex]::Escape($file)
    $allOk = (Test-Check $ok ("install_all.sql references " + $file)) -and $allOk
}

$schema = Get-Content (Join-Path $DbDir '001_initial_schema.sql') -Raw
foreach ($table in $ExpectedTables) {
    $pattern = 'CREATE TABLE ' + $table + '\s*\('
    $ok = $schema -match $pattern
    $allOk = (Test-Check $ok ("Table in 001 - " + $table)) -and $allOk
}

$createBlocks = [regex]::Matches($schema, 'CREATE TABLE (\w+)[\s\S]*?;')
$uuidPkOk = $true
foreach ($m in $createBlocks) {
    $name = $m.Groups[1].Value
    $block = $m.Value
    if ($block -notmatch 'PRIMARY KEY') {
        $null = Test-Check $false ("PK missing - " + $name)
        $uuidPkOk = $false
    }
}
$allOk = (Test-Check $uuidPkOk 'All tables have PRIMARY KEY') -and $allOk

$constraints = Get-Content (Join-Path $DbDir '003_constraints.sql') -Raw
$fkCount = ([regex]::Matches($constraints, 'FOREIGN KEY')).Count
$allOk = (Test-Check ($fkCount -ge 80) ("Foreign keys - " + $fkCount)) -and $allOk

$softDeleteTables = @(
    'users', 'products', 'customers', 'suppliers', 'sales_invoices',
    'purchase_invoices', 'expenses', 'product_categories', 'product_units'
)
foreach ($t in $softDeleteTables) {
    $pattern = 'CREATE TABLE ' + $t + '[\s\S]*?deleted_at'
    $ok = $schema -match $pattern
    $allOk = (Test-Check $ok ("Soft delete - " + $t)) -and $allOk
}

$allOk = (Test-Check ($schema -match 'CREATE TABLE sync_conflicts') 'sync_conflicts table present') -and $allOk

$phpFiles = Get-ChildItem $DbDir -Filter '*.php' -ErrorAction SilentlyContinue
$allOk = (Test-Check ($phpFiles.Count -eq 0) 'No PHP in database/') -and $allOk

if (-not $SkipLive) {
    Write-Host ''
    Write-Host '=== Live PostgreSQL Validation ===' -ForegroundColor Cyan

    $psql = $null
    $candidates = @(
        'psql',
        'D:\MizaPos\cloud\api\tools\pgsql\pgsql\bin\psql.exe',
        'C:\Program Files\PostgreSQL\17\bin\psql.exe',
        'C:\Program Files\PostgreSQL\16\bin\psql.exe',
        'C:\Program Files\PostgreSQL\15\bin\psql.exe'
    )
    foreach ($c in $candidates) {
        if ($c -eq 'psql') {
            if (Get-Command psql -ErrorAction SilentlyContinue) { $psql = 'psql'; break }
        }
        elseif (Test-Path $c) { $psql = $c; break }
    }

    if (-not $psql) {
        Write-Host '[SKIP] psql not found - static checks only' -ForegroundColor Yellow
    }
    else {
        if (-not $env:PGPASSWORD) { $env:PGPASSWORD = '' }
        & $psql -U $PostgresUser -d postgres -v ON_ERROR_STOP=1 -c ("DROP DATABASE IF EXISTS " + $Database) 2>$null | Out-Null
        & $psql -U $PostgresUser -d postgres -v ON_ERROR_STOP=1 -c ("CREATE DATABASE " + $Database)
        if ($LASTEXITCODE -ne 0) {
            Write-Host '[SKIP] Cannot create temp database' -ForegroundColor Yellow
        }
        else {
            Push-Location $DbDir
            try {
                & $psql -U $PostgresUser -d $Database -v ON_ERROR_STOP=1 -f install_all.sql
                $liveOk = ($LASTEXITCODE -eq 0)
                $allOk = (Test-Check $liveOk ("Live install_all.sql on " + $Database)) -and $allOk

                if ($liveOk) {
                    $tableCount = & $psql -U $PostgresUser -d $Database -t -A -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';"
                    $allOk = (Test-Check ([int]$tableCount -ge 44) ("Tables created - " + $tableCount)) -and $allOk

                    $seedCount = & $psql -U $PostgresUser -d $Database -t -A -c "SELECT count(*) FROM subscription_plans;"
                    $allOk = (Test-Check ([int]$seedCount -eq 5) ("Seed plans - " + $seedCount)) -and $allOk

                    $migCount = & $psql -U $PostgresUser -d $Database -t -A -c "SELECT count(*) FROM schema_migrations WHERE version >= '010';"
                    $allOk = (Test-Check ([int]$migCount -eq 8) ("Extension migrations 010-017 - " + $migCount)) -and $allOk

                    $postedAt = & $psql -U $PostgresUser -d $Database -t -A -c "SELECT count(*) FROM information_schema.columns WHERE table_name='sales_invoices' AND column_name='posted_at';"
                    $allOk = (Test-Check ([int]$postedAt -eq 1) 'sales_invoices.posted_at column') -and $allOk
                }
            }
            finally {
                Pop-Location
            }
            & $psql -U $PostgresUser -d postgres -c ("DROP DATABASE IF EXISTS " + $Database) 2>$null | Out-Null
        }
    }
}

Write-Host ''
if ($allOk) {
    Write-Host 'SQL validation PASSED.' -ForegroundColor Green
    exit 0
}
else {
    Write-Host 'SQL validation FAILED.' -ForegroundColor Red
    exit 1
}
