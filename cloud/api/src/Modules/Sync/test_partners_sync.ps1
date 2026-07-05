#Requires -Version 5.1
param([string]$BaseUrl = 'http://127.0.0.1:8787')

$companyId = '550e8400-e29b-41d4-a716-446655440000'
$branchId = '660e8400-e29b-41d4-a716-446655440001'
$deviceId = '770e8400-e29b-41d4-a716-446655440002'
$installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
$customerId = 'c100e840-e29b-41d4-a716-446655440040'
$supplierId = 'c200e840-e29b-41d4-a716-446655440041'

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
        name = 'customers'; entity_type = 'customer'; entity_id = $customerId
        payload = @{
            id = $customerId; company_id = $companyId; branch_id = $branchId
            name = 'Test Customer'; partner_number = 'C-900'; credit_limit = 1200
        }
    },
    @{
        name = 'suppliers'; entity_type = 'supplier'; entity_id = $supplierId
        payload = @{
            id = $supplierId; company_id = $companyId; branch_id = $branchId
            name = 'Test Supplier'; partner_number = 'S-900'
        }
    }
)

foreach ($entity in $entities) {
    Write-Host "Push $($entity.name)" -ForegroundColor Cyan
    $batchId = [guid]::NewGuid().ToString()
    $push = Invoke-Api POST "/v1/sync/push/$($entity.name)" @{
        company_id = $companyId; branch_id = $branchId; device_id = $deviceId; batch_id = $batchId
        events = @(@{
            entity_type = $entity.entity_type; entity_id = $entity.entity_id; operation = 'create'
            outbox_id = [guid]::NewGuid().ToString(); idempotency_key = "$deviceId`:$($entity.entity_id):create:$batchId"
            client_row_version = 1; payload_json = $entity.payload
        })
    } $headers
    if ($push.Status -notin 200, 202) {
        throw "Push $($entity.name) failed: $($push.Raw)"
    }

    Write-Host "Pull $($entity.name)" -ForegroundColor Cyan
    $pull = Invoke-Api GET "/v1/sync/pull/$($entity.name)?company_id=$companyId&branch_id=$branchId&since_sequence=0&limit=50" $null $headers
    if ($pull.Status -ne 200) {
        throw "Pull $($entity.name) failed: $($pull.Raw)"
    }
    $entries = $pull.Json.data.entries
    if (-not $entries -or $entries.Count -lt 1) {
        throw "Pull $($entity.name) returned no entries"
    }
    Write-Host "  OK — $($entries.Count) entr(y/ies), last_sequence=$($pull.Json.meta.last_sequence)" -ForegroundColor Green
}

Write-Host 'REST list customers + suppliers' -ForegroundColor Cyan
$listCustomers = Invoke-Api GET "/v1/customers?branch_id=$branchId" $null @{ Authorization = "Bearer $userToken"; 'X-Company-ID' = $companyId; 'X-Branch-ID' = $branchId }
$listSuppliers = Invoke-Api GET "/v1/suppliers?branch_id=$branchId" $null @{ Authorization = "Bearer $userToken"; 'X-Company-ID' = $companyId; 'X-Branch-ID' = $branchId }
if ($listCustomers.Status -ne 200 -or $listSuppliers.Status -ne 200) {
    throw 'REST list failed'
}
Write-Host 'All partner sync tests passed.' -ForegroundColor Green
