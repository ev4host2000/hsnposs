#Requires -Version 5.1
param([string]$BaseUrl = 'http://127.0.0.1:8787')

$companyId = '550e8400-e29b-41d4-a716-446655440000'
$branchId = '660e8400-e29b-41d4-a716-446655440001'
$deviceId = '770e8400-e29b-41d4-a716-446655440002'
$installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
$productId = 'a100e840-e29b-41d4-a716-446655440020'

function Invoke-Api {
    param([string]$Method, [string]$Path, [hashtable]$Body = $null, [hashtable]$Headers = @{})
    $params = @{
        Uri = "$BaseUrl$Path"
        Method = $Method
        Headers = @{ 'Content-Type' = 'application/json' } + $Headers
    }
    if ($Body) { $params['Body'] = ($Body | ConvertTo-Json -Depth 8) }
    try {
        $r = Invoke-WebRequest @params -UseBasicParsing
        return @{ Status = $r.StatusCode; Json = ($r.Content | ConvertFrom-Json); Raw = $r.Content }
    } catch {
        $resp = $_.Exception.Response
        if ($null -eq $resp) { throw $_ }
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $body = $reader.ReadToEnd()
        $json = $null
        if ($body.Trim()) {
            try { $json = $body | ConvertFrom-Json } catch { $json = @{ raw = $body } }
        }
        return @{ Status = [int]$resp.StatusCode; Json = $json; Raw = $body }
    }
}

Write-Host '1) Login' -ForegroundColor Cyan
$login = Invoke-Api POST '/v1/auth/login' @{
    username = 'owner@store.com'
    password = 'MizaTest123!'
    company_id = $companyId
    branch_id = $branchId
    device_id = $deviceId
    installation_id = $installationId
}
$userToken = $login.Json.data.access_token
Write-Host "   -> $($login.Status)"

Write-Host '2) Register device' -ForegroundColor Cyan
$reg = Invoke-Api POST '/v1/devices/register' @{
    installation_id = $installationId
    device_fingerprint = 'sha256:test-fingerprint'
    platform = 'android'
    device_name = 'Samsung A54'
    os_name = 'Android 14'
    app_version = '1.0.37'
    company_id = $companyId
    branch_id = $branchId
    registered_by_user_id = '990e8400-e29b-41d4-a716-446655440004'
} @{
    Authorization = "Bearer $userToken"
    'X-Company-ID' = $companyId
    'X-Branch-ID' = $branchId
}
$deviceToken = $reg.Json.data.access_token
Write-Host "   -> $($reg.Status)"

Write-Host '3) Push product (Device A)' -ForegroundColor Cyan
$batchId = [guid]::NewGuid().ToString()
$outboxId = [guid]::NewGuid().ToString()
$pushBody = '{"company_id":"' + $companyId + '","branch_id":"' + $branchId + '","device_id":"' + $deviceId + '","batch_id":"' + $batchId + '","events":[{"outbox_id":"' + $outboxId + '","entity_type":"product","entity_id":"' + $productId + '","operation":"create","payload_json":{"id":"' + $productId + '","company_id":"' + $companyId + '","branch_id":"' + $branchId + '","name":"Milk","sale_price":6.5,"cost_price":5.0,"stock_qty":48},"client_row_version":1,"idempotency_key":"' + $deviceId + ':' + $productId + ':create","occurred_at":"2026-07-05T10:00:00.000Z"}]}'
try {
    $pushResp = Invoke-WebRequest -Uri "$BaseUrl/v1/sync/push/products" -Method POST `
        -ContentType 'application/json; charset=utf-8' `
        -Headers @{
            Authorization = "Bearer $deviceToken"
            'X-Device-ID' = $deviceId
            'X-Company-ID' = $companyId
            'X-Branch-ID' = $branchId
            'Idempotency-Key' = $batchId
        } `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($pushBody)) `
        -UseBasicParsing
    $push = @{ Status = $pushResp.StatusCode; Json = ($pushResp.Content | ConvertFrom-Json); Raw = $pushResp.Content }
} catch {
    $resp = $_.Exception.Response
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $raw = $reader.ReadToEnd()
    $push = @{ Status = [int]$resp.StatusCode; Json = ($raw | ConvertFrom-Json); Raw = $raw }
}
Write-Host "   -> $($push.Status) accepted=$($push.Json.data.accepted)"

Write-Host '4) Pull products (Device B simulation)' -ForegroundColor Cyan
$pull = Invoke-Api GET "/v1/sync/pull/products?company_id=$companyId&branch_id=$branchId&since_sequence=0" $null @{
    Authorization = "Bearer $deviceToken"
    'X-Device-ID' = $deviceId
    'X-Company-ID' = $companyId
}
$entries = $pull.Json.data.entries
Write-Host "   -> $($pull.Status) entries=$($entries.Count)"
if ($entries.Count -gt 0) {
    Write-Host "   product: $($entries[0].payload_json.name) id=$($entries[0].entity_id)"
}

if ($push.Status -in 200,202 -and $pull.Status -eq 200 -and $entries.Count -ge 1 -and $entries[0].entity_id -eq $productId) {
    Write-Host "`nProducts sync scenario PASSED" -ForegroundColor Green
    exit 0
}

Write-Host "`nProducts sync scenario FAILED" -ForegroundColor Red
Write-Host $push.Raw
Write-Host $pull.Raw
exit 1
