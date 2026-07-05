# Auth module — local DB bootstrap
# Requires: PostgreSQL client (psql) + database `mizacloud` created

param(
    [string]$Psql = 'psql',
    [string]$DbName = 'mizacloud',
    [string]$DbUser = 'postgres'
)

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$dbDir = Join-Path $root 'database'
$seed = Join-Path $PSScriptRoot 'database\dev_seed.sql'

Write-Host "Applying dev seed to $DbName..." -ForegroundColor Cyan
& $Psql -U $DbUser -d $DbName -f $seed
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Seed applied. Test user: owner@store.com / MizaTest123!" -ForegroundColor Green
