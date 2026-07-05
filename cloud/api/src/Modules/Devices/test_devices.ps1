#Requires -Version 5.1
param([string]$BaseUrl = 'http://127.0.0.1:8787')

$companyId = '550e8400-e29b-41d4-a716-446655440000'
$branchId = '660e8400-e29b-41d4-a716-446655440001'
$installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

function Invoke-Api {
    param([string]$Method, [string]$Path, [hashtable]$Body = $null, [hashtable]$Headers = @{})
    $params = @{
        Uri = "$BaseUrl$Path"
        Method = $Method
        Headers = @{ 'Content-Type' = 'application/json' } + $Headers
    }
    if ($Body) { $params['Body'] = ($Body | ConvertTo-Json -Depth 6) }
    try {
        $r = Invoke-WebRequest @params -UseBasicParsing
        return @{ Status = $r.StatusCode; Json = ($r.Content | ConvertFrom-Json) }
    } catch {
        $resp = $_.Exception.Response
        if ($null -eq $resp) { throw $_ }
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $body = $reader.ReadToEnd()
        $json = $null
        if ($body.Trim()) { $json = $body | ConvertFrom-Json }
        return @{ Status = [int]$resp.StatusCode; Json = $json; Raw = $body }
    }
}

Write-Host '1) Login' -ForegroundColor Cyan
$login = Invoke-Api POST '/v1/auth/login' @{
    username = 'owner@store.com'
    password = 'MizaTest123!'
    company_id = $companyId
    branch_id = $branchId
    device_id = '770e8400-e29b-41d4-a716-446655440002'
    installation_id = $installationId
}
$userToken = $login.Json.data.access_token
Write-Host "   -> $($login.Status)"

Write-Host '2) Register device (expect 200 reused)' -ForegroundColor Cyan
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
$deviceId = $reg.Json.data.device_id
Write-Host "   -> $($reg.Status) device_id=$deviceId reused=$($reg.Status -eq 200)"

Write-Host '3) GET /devices/me' -ForegroundColor Cyan
$me = Invoke-Api GET '/v1/devices/me' $null @{
    Authorization = "Bearer $deviceToken"
    'X-Device-ID' = $deviceId
    'X-Company-ID' = $companyId
}
Write-Host "   -> $($me.Status) installation=$($me.Json.data.installation_id)"

Write-Host '4) POST /devices/heartbeat' -ForegroundColor Cyan
$hb = Invoke-Api POST '/v1/devices/heartbeat' @{ app_version = '1.0.38' } @{
    Authorization = "Bearer $deviceToken"
    'X-Device-ID' = $deviceId
}
Write-Host "   -> $($hb.Status) last_seen=$($hb.Json.data.last_seen_at)"

Write-Host "`nDevice tests completed." -ForegroundColor Green
