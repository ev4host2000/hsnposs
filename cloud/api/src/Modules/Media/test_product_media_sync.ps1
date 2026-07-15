#Requires -Version 5.1
param([string]$BaseUrl = 'http://127.0.0.1:8787')

$companyId = '550e8400-e29b-41d4-a716-446655440000'
$branchId = '660e8400-e29b-41d4-a716-446655440001'
$deviceId = '770e8400-e29b-41d4-a716-446655440002'
$installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
$productId = 'a100e840-e29b-41d4-a716-446655440099'

function Invoke-ApiJson {
    param([string]$Method, [string]$Path, [hashtable]$Body = $null, [hashtable]$Headers = @{})
    $params = @{
        Uri = "$BaseUrl$Path"
        Method = $Method
        Headers = @{ 'Content-Type' = 'application/json' } + $Headers
    }
    if ($Body) { $params['Body'] = ($Body | ConvertTo-Json -Depth 8) }
    $r = Invoke-WebRequest @params -UseBasicParsing
    return @{ Status = $r.StatusCode; Json = ($r.Content | ConvertFrom-Json); Raw = $r.Content }
}

Write-Host '1) Login + register device' -ForegroundColor Cyan
$login = Invoke-ApiJson POST '/v1/auth/login' @{
    username = 'owner@store.com'
    password = 'MizaTest123!'
    company_id = $companyId
    branch_id = $branchId
    device_id = $deviceId
    installation_id = $installationId
}
$userToken = $login.Json.data.access_token
$reg = Invoke-ApiJson POST '/v1/devices/register' @{
    installation_id = $installationId
    device_fingerprint = 'sha256:test-fingerprint'
    platform = 'android'
    device_name = 'Media Test'
    os_name = 'Android 14'
    app_version = '1.0.37'
    company_id = $companyId
    branch_id = $branchId
    registered_by_user_id = '990e8400-e29b-41d4-a716-446655440004'
} @{ Authorization = "Bearer $userToken" }
$deviceToken = $reg.Json.data.access_token

Write-Host '2) Push product shell' -ForegroundColor Cyan
$batchId = [guid]::NewGuid().ToString()
$outboxId = [guid]::NewGuid().ToString()
$pushBody = '{"company_id":"' + $companyId + '","branch_id":"' + $branchId + '","device_id":"' + $deviceId + '","batch_id":"' + $batchId + '","events":[{"outbox_id":"' + $outboxId + '","entity_type":"product","entity_id":"' + $productId + '","operation":"create","payload_json":{"id":"' + $productId + '","company_id":"' + $companyId + '","branch_id":"' + $branchId + '","name":"Image Test Product","sale_price":10,"cost_price":8,"stock_qty":1},"client_row_version":1,"idempotency_key":"' + $deviceId + ':' + $productId + ':create","occurred_at":"2026-07-09T10:00:00.000Z"}]}'
Invoke-WebRequest -Uri "$BaseUrl/v1/sync/push/products" -Method POST `
    -ContentType 'application/json; charset=utf-8' `
    -Headers @{
        Authorization = "Bearer $deviceToken"
        'X-Device-ID' = $deviceId
        'X-Company-ID' = $companyId
        'X-Branch-ID' = $branchId
        'Idempotency-Key' = $batchId
    } `
    -Body ([System.Text.Encoding]::UTF8.GetBytes($pushBody)) `
    -UseBasicParsing | Out-Null

Write-Host '3) Upload PNG' -ForegroundColor Cyan
$png = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')
$tmp = Join-Path $env:TEMP 'miza-test-product.png'
[IO.File]::WriteAllBytes($tmp, $png)

$form = @{
    image = Get-Item -LiteralPath $tmp
}
$upload = Invoke-WebRequest -Uri "$BaseUrl/v1/media/products/$productId" -Method POST `
    -Headers @{
        Authorization = "Bearer $deviceToken"
        'X-Device-ID' = $deviceId
        'X-Company-ID' = $companyId
        'X-Branch-ID' = $branchId
    } `
    -Form $form `
    -UseBasicParsing
$uploadJson = $upload.Content | ConvertFrom-Json
$imageUrl = $uploadJson.data.image_url
Write-Host "   image_url: $imageUrl"

Write-Host '4) Fetch media' -ForegroundColor Cyan
$img = Invoke-WebRequest -Uri $imageUrl -UseBasicParsing
if ($img.StatusCode -ne 200) { throw 'Media GET failed' }
Write-Host '   media GET OK' -ForegroundColor Green

Write-Host '5) Push product with image_url' -ForegroundColor Cyan
$batchId2 = [guid]::NewGuid().ToString()
$outboxId2 = [guid]::NewGuid().ToString()
$pushBody2 = '{"company_id":"' + $companyId + '","branch_id":"' + $branchId + '","device_id":"' + $deviceId + '","batch_id":"' + $batchId2 + '","events":[{"outbox_id":"' + $outboxId2 + '","entity_type":"product","entity_id":"' + $productId + '","operation":"update","payload_json":{"id":"' + $productId + '","company_id":"' + $companyId + '","branch_id":"' + $branchId + '","name":"Image Test Product","sale_price":10,"cost_price":8,"stock_qty":1,"image_url":"' + $imageUrl + '"},"client_row_version":2,"idempotency_key":"' + $deviceId + ':' + $productId + ':update2","occurred_at":"2026-07-09T10:01:00.000Z"}]}'
Invoke-WebRequest -Uri "$BaseUrl/v1/sync/push/products" -Method POST `
    -ContentType 'application/json; charset=utf-8' `
    -Headers @{
        Authorization = "Bearer $deviceToken"
        'X-Device-ID' = $deviceId
        'X-Company-ID' = $companyId
        'X-Branch-ID' = $branchId
        'Idempotency-Key' = $batchId2
    } `
    -Body ([System.Text.Encoding]::UTF8.GetBytes($pushBody2)) `
    -UseBasicParsing | Out-Null

Write-Host '6) Pull and verify image_url in changelog' -ForegroundColor Cyan
$pull = Invoke-WebRequest -Uri "$BaseUrl/v1/sync/pull/products?company_id=$companyId&branch_id=$branchId&since_sequence=0&limit=50" `
    -Headers @{ Authorization = "Bearer $deviceToken" } `
    -UseBasicParsing
$pullJson = $pull.Content | ConvertFrom-Json
$entry = $pullJson.data.entries | Where-Object { $_.entity_id -eq $productId } | Select-Object -Last 1
if (-not $entry.payload_json.image_url) { throw 'image_url missing in pull payload' }
Write-Host 'Product media sync OK' -ForegroundColor Green
