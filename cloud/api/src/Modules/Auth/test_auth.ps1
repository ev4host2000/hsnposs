#Requires -Version 5.1
<#
.SYNOPSIS
    End-to-end auth API smoke test (requires PostgreSQL + dev_seed.sql).
#>
param(
    [string]$BaseUrl = 'http://127.0.0.1:8787'
)

$ErrorActionPreference = 'Stop'

$companyId = '550e8400-e29b-41d4-a716-446655440000'
$branchId = '660e8400-e29b-41d4-a716-446655440001'
$deviceId = '770e8400-e29b-41d4-a716-446655440002'
$installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

function Invoke-Api {
    param(
        [string]$Method,
        [string]$Path,
        [hashtable]$Body = $null,
        [string]$Token = $null
    )
    $headers = @{ 'Content-Type' = 'application/json' }
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }
    $params = @{
        Uri = "$BaseUrl$Path"
        Method = $Method
        Headers = $headers
    }
    if ($Body) { $params['Body'] = ($Body | ConvertTo-Json -Depth 6) }
    try {
        $resp = Invoke-WebRequest @params -UseBasicParsing
        return @{ Status = $resp.StatusCode; Json = ($resp.Content | ConvertFrom-Json) }
    }
    catch {
        $r = $_.Exception.Response
        $reader = New-Object System.IO.StreamReader($r.GetResponseStream())
        $content = $reader.ReadToEnd()
        return @{ Status = [int]$r.StatusCode; Json = ($content | ConvertFrom-Json) }
    }
}

Write-Host "1) POST /v1/auth/login" -ForegroundColor Cyan
$login = Invoke-Api -Method POST -Path '/v1/auth/login' -Body @{
    username = 'owner@store.com'
    password = 'MizaTest123!'
    company_id = $companyId
    branch_id = $branchId
    device_id = $deviceId
    installation_id = $installationId
}
Write-Host "   -> $($login.Status) ok=$($login.Json.ok)"
if (-not $login.Json.ok) { exit 1 }
$access = $login.Json.data.access_token
$refresh = $login.Json.data.refresh_token

Write-Host "2) GET /v1/auth/me" -ForegroundColor Cyan
$me = Invoke-Api -Method GET -Path '/v1/auth/me' -Token $access
Write-Host "   -> $($me.Status) user=$($me.Json.data.user.username)"

Write-Host "3) POST /v1/auth/token/refresh" -ForegroundColor Cyan
$ref = Invoke-Api -Method POST -Path '/v1/auth/token/refresh' -Body @{
    refresh_token = $refresh
    device_id = $deviceId
    installation_id = $installationId
}
Write-Host "   -> $($ref.Status) ok=$($ref.Json.ok)"
$access2 = $ref.Json.data.access_token
$refresh2 = $ref.Json.data.refresh_token

Write-Host "4) POST /v1/auth/logout" -ForegroundColor Cyan
$out = Invoke-Api -Method POST -Path '/v1/auth/logout' -Token $access2 -Body @{
    refresh_token = $refresh2
    revoke_all_sessions = $false
}
Write-Host "   -> $($out.Status) revoked=$($out.Json.data.revoked)"

Write-Host "5) GET /v1/auth/me (expect 401)" -ForegroundColor Cyan
$me2 = Invoke-Api -Method GET -Path '/v1/auth/me' -Token $access2
Write-Host "   -> $($me2.Status) ok=$($me2.Json.ok)"

Write-Host "`nAuth smoke test completed." -ForegroundColor Green
