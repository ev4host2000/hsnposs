#Requires -Version 5.1
param([string]$BaseUrl = 'http://127.0.0.1:8787')

$companyId = '550e8400-e29b-41d4-a716-446655440000'
$branchId = '660e8400-e29b-41d4-a716-446655440001'
$deviceId = '770e8400-e29b-41d4-a716-446655440002'
$installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

$categoryId = 'b100e840-e29b-41d4-a716-446655440030'
$unitId = 'b200e840-e29b-41d4-a716-446655440031'
$taxId = 'b300e840-e29b-41d4-a716-446655440032'
$priceListId = 'b400e840-e29b-41d4-a716-446655440033'
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
        if ($body.Trim()) { try { $json = $body | ConvertFrom-Json } catch { $json = @{ raw = $body } } }
        return @{ Status = [int]$resp.StatusCode; Json = $json; Raw = $body }
    }
}

Write-Host 'Login + register device' -ForegroundColor Cyan
$login = Invoke-Api POST '/v1/auth/login' @{
    username = 'owner@store.com'; password = 'MizaTest123!'
    company_id = $companyId; branch_id = $branchId
    device_id = $deviceId; installation_id = $installationId
}
$userToken = $login.Json.data.access_token
$reg = Invoke-Api POST '/v1/devices/register' @{
    installation_id = $installationId; device_fingerprint = 'sha256:test'
    platform = 'android'; device_name = 'Test'; os_name = 'Android 14'; app_version = '1.0.37'
    company_id = $companyId; branch_id = $branchId
    registered_by_user_id = '990e8400-e29b-41d4-a716-446655440004'
} @{ Authorization = "Bearer $userToken"; 'X-Company-ID' = $companyId; 'X-Branch-ID' = $branchId }
$deviceToken = $reg.Json.data.access_token
$headers = @{
    Authorization = "Bearer $deviceToken"
    'X-Device-ID' = $deviceId
    'X-Company-ID' = $companyId
    'X-Branch-ID' = $branchId
}

$entities = @(
    @{
        name = 'product-categories'; entity_type = 'product_category'; entity_id = $categoryId
        payload = @{ id = $categoryId; company_id = $companyId; branch_id = $branchId; name = 'Dairy'; sort_order = 1 }
    },
    @{
        name = 'product-units'; entity_type = 'product_unit'; entity_id = $unitId
        payload = @{ id = $unitId; company_id = $companyId; branch_id = $branchId; name = 'kg' }
    },
    @{
        name = 'taxes'; entity_type = 'tax'; entity_id = $taxId
        payload = @{ id = $taxId; company_id = $companyId; branch_id = $branchId; name = 'VAT'; percent = 15; is_default = $true; sort_order = 1 }
    },
    @{
        name = 'price-lists'; entity_type = 'price_list'; entity_id = $priceListId
        payload = @{ id = $priceListId; company_id = $companyId; branch_id = $branchId; name = 'Retail'; is_default = $true; sort_order = 1; items = @(@{ product_id = $productId; sale_price = 7.5 }) }
    },
    @{
        name = 'products'; entity_type = 'product'; entity_id = $productId
        payload = @{ id = $productId; company_id = $companyId; branch_id = $branchId; name = 'Milk'; sale_price = 6.5; cost_price = 5; stock_qty = 48; category_id = $categoryId; unit_name = 'kg' }
    }
)

$failed = $false
foreach ($entity in $entities) {
    Write-Host "Push $($entity.name)" -ForegroundColor Cyan
    $batchId = [guid]::NewGuid().ToString()
    $outboxId = [guid]::NewGuid().ToString()
    $pushBody = @{
        company_id = $companyId; branch_id = $branchId; device_id = $deviceId; batch_id = $batchId
        events = @(@{
            outbox_id = $outboxId; entity_type = $entity.entity_type; entity_id = $entity.entity_id
            operation = 'create'; payload_json = $entity.payload; client_row_version = 1
            idempotency_key = "$deviceId`:$($entity.entity_id):create"; occurred_at = '2026-07-05T10:00:00.000Z'
        })
    }
    $push = Invoke-Api POST "/v1/sync/push/$($entity.name)" $pushBody ($headers + @{ 'Idempotency-Key' = $batchId })
    Write-Host "  push -> $($push.Status) accepted=$($push.Json.data.accepted)"

    Write-Host "Pull $($entity.name)" -ForegroundColor Cyan
    $pull = Invoke-Api GET "/v1/sync/pull/$($entity.name)?company_id=$companyId&branch_id=$branchId&since_sequence=0" $null $headers
    $count = $pull.Json.data.entries.Count
    Write-Host "  pull -> $($pull.Status) entries=$count"

    if ($push.Status -notin 200,202 -or $pull.Status -ne 200 -or $count -lt 1) {
        $failed = $true
        Write-Host $push.Raw
        Write-Host $pull.Raw
    }
}

if ($failed) {
    Write-Host "`nCatalog sync scenario FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "`nCatalog sync scenario PASSED" -ForegroundColor Green
exit 0
