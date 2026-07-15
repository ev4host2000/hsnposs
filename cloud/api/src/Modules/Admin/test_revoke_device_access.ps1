#Requires -Version 5.1
<#
.SYNOPSIS
  RAP-P0-01 acceptance: after Ops device revoke, access token must fail immediately;
  refresh must fail; a second active device session must keep working.

.NOTES
  Requires: API + DB (local docker or reachable BaseUrl), Ops admin credentials,
  and a seed/login-capable company with room for a temporary second device.
#>
param(
    [string]$BaseUrl = 'http://127.0.0.1:8787',
    [string]$OpsEmail = '',
    [string]$OpsPassword = '',
    [switch]$RequireOps,
    [string]$CompanyId = '550e8400-e29b-41d4-a716-446655440000',
    [string]$BranchId = '660e8400-e29b-41d4-a716-446655440001',
    [string]$SeedDeviceId = '770e8400-e29b-41d4-a716-446655440002',
    [string]$SeedInstallationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    [string]$OwnerUser = 'owner@store.com',
    [string]$OwnerPassword = 'MizaTest123!'
)

$ErrorActionPreference = 'Stop'
$failed = 0

if (-not $OpsEmail -and $env:MIZA_OPS_EMAIL) { $OpsEmail = $env:MIZA_OPS_EMAIL }
if (-not $OpsPassword -and $env:MIZA_OPS_PASSWORD) { $OpsPassword = $env:MIZA_OPS_PASSWORD }
if ($env:MIZA_ACCEPTANCE_BASE_URL -and $BaseUrl -eq 'http://127.0.0.1:8787') {
    $BaseUrl = $env:MIZA_ACCEPTANCE_BASE_URL
}

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
        Uri             = "$BaseUrl$Path"
        Method          = $Method
        Headers         = $headers
        UseBasicParsing = $true
    }
    if ($Body) { $params['Body'] = ($Body | ConvertTo-Json -Depth 8) }
    try {
        $resp = Invoke-WebRequest @params
        return @{ Status = [int]$resp.StatusCode; Json = ($resp.Content | ConvertFrom-Json); Ok = $true }
    } catch {
        $r = $_.Exception.Response
        if ($null -eq $r) { throw $_ }
        $reader = New-Object System.IO.StreamReader($r.GetResponseStream())
        $content = $reader.ReadToEnd()
        $json = $null
        if ($content.Trim()) {
            try { $json = $content | ConvertFrom-Json } catch { $json = $null }
        }
        return @{ Status = [int]$r.StatusCode; Json = $json; Ok = $false; Raw = $content }
    }
}

function Assert-Step {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        Write-Host "PASS  $Name $Detail" -ForegroundColor Green
    } else {
        Write-Host "FAIL  $Name $Detail" -ForegroundColor Red
        $script:failed++
    }
}

Write-Host "=== RAP-P0-01 revoke access token acceptance ===" -ForegroundColor Cyan
Write-Host "BaseUrl=$BaseUrl"

# --- Auth: login / refresh / logout smoke (seed device) ---
Write-Host "`n-- Auth smoke (seed device) --" -ForegroundColor Cyan
$login = Invoke-Api POST '/v1/auth/login' @{
    username        = $OwnerUser
    password        = $OwnerPassword
    company_id      = $CompanyId
    branch_id       = $BranchId
    device_id       = $SeedDeviceId
    installation_id = $SeedInstallationId
}
Assert-Step 'login seed device' ($login.Status -eq 200 -and $login.Json.ok) "status=$($login.Status)"
$seedAccess = $login.Json.data.access_token
$seedRefresh = $login.Json.data.refresh_token

$me = Invoke-Api GET '/v1/auth/me' -Token $seedAccess
Assert-Step 'access token validates (/auth/me)' ($me.Status -eq 200 -and $me.Json.ok) "status=$($me.Status)"

$ref = Invoke-Api POST '/v1/auth/token/refresh' @{
    refresh_token   = $seedRefresh
    device_id       = $SeedDeviceId
    installation_id = $SeedInstallationId
}
Assert-Step 'refresh works' ($ref.Status -eq 200 -and $ref.Json.ok) "status=$($ref.Status)"
$seedAccess2 = $ref.Json.data.access_token
$seedRefresh2 = $ref.Json.data.refresh_token

$out = Invoke-Api POST '/v1/auth/logout' -Token $seedAccess2 -Body @{
    refresh_token       = $seedRefresh2
    revoke_all_sessions = $false
}
Assert-Step 'logout works' ($out.Status -eq 200 -and $out.Json.data.revoked -eq $true) "status=$($out.Status)"

$meAfterLogout = Invoke-Api GET '/v1/auth/me' -Token $seedAccess2
Assert-Step 'access invalidated after logout' ($meAfterLogout.Status -eq 401) "status=$($meAfterLogout.Status)"

# Re-login seed for later "other device still works" check
$loginSeed2 = Invoke-Api POST '/v1/auth/login' @{
    username        = $OwnerUser
    password        = $OwnerPassword
    company_id      = $CompanyId
    branch_id       = $BranchId
    device_id       = $SeedDeviceId
    installation_id = $SeedInstallationId
}
$keepAccess = $loginSeed2.Json.data.access_token
Assert-Step 're-login seed for active session check' ($loginSeed2.Status -eq 200 -and $loginSeed2.Json.ok)

if (-not $OpsEmail -or -not $OpsPassword) {
    $msg = 'Ops credentials required for revoke acceptance (set -OpsEmail/-OpsPassword or MIZA_OPS_EMAIL/MIZA_OPS_PASSWORD).'
    if ($RequireOps) {
        Assert-Step 'ops credentials provided' $false $msg
    } else {
        Write-Host "FAIL  $msg" -ForegroundColor Red
        $script:failed++
    }
    if ($failed -gt 0) {
        Write-Host "`nFAILED=$failed (no silent skip - revoke path not executed)" -ForegroundColor Red
        exit 1
    }
}

# --- Pairing + register ephemeral device, then Ops revoke ---
Write-Host "`n-- Ops revoke ephemeral device --" -ForegroundColor Cyan
$pair = Invoke-Api POST '/v1/auth/login' @{
    username   = $OwnerUser
    password   = $OwnerPassword
    company_id = $CompanyId
    branch_id  = $BranchId
}
Assert-Step 'pairing login' ($pair.Status -eq 200 -and $pair.Json.ok) "status=$($pair.Status)"
$pairToken = $pair.Json.data.access_token

$ephemeralInstall = [guid]::NewGuid().ToString()
$reg = Invoke-Api POST '/v1/devices/register' @{
    installation_id      = $ephemeralInstall
    device_fingerprint   = ("sha256:rap-p0-01-" + $ephemeralInstall)
    platform             = 'android'
    device_name          = 'RAP-P0-01 Test Device'
    os_name              = 'Android 14'
    app_version          = '1.0.0-test'
    company_id           = $CompanyId
    branch_id            = $BranchId
} -Token $pairToken
Assert-Step 'register ephemeral device' ($reg.Status -in 200, 201 -and $reg.Json.ok) "status=$($reg.Status)"
$ephemeralDeviceId = [string]$reg.Json.data.device_id

$ephemeralLogin = Invoke-Api POST '/v1/auth/login' @{
    username        = $OwnerUser
    password        = $OwnerPassword
    company_id      = $CompanyId
    branch_id       = $BranchId
    device_id       = $ephemeralDeviceId
    installation_id = $ephemeralInstall
}
Assert-Step 'login ephemeral device' ($ephemeralLogin.Status -eq 200 -and $ephemeralLogin.Json.ok)
$ephemeralAccess = $ephemeralLogin.Json.data.access_token
$ephemeralRefresh = $ephemeralLogin.Json.data.refresh_token

$meEph = Invoke-Api GET '/v1/auth/me' -Token $ephemeralAccess
Assert-Step 'ephemeral access works before revoke' ($meEph.Status -eq 200 -and $meEph.Json.ok)

$opsLogin = Invoke-Api POST '/v1/admin/auth/login' @{
    email    = $OpsEmail
    password = $OpsPassword
}
Assert-Step 'ops admin login' ($opsLogin.Status -eq 200 -and $opsLogin.Json.ok) "status=$($opsLogin.Status)"
$opsToken = $opsLogin.Json.data.access_token

$revoke = Invoke-Api POST "/v1/admin/devices/$ephemeralDeviceId/revoke" -Token $opsToken
Assert-Step 'ops revoke device' ($revoke.Status -eq 200 -and $revoke.Json.data.revoked -eq $true) "status=$($revoke.Status)"

$meAfterRevoke = Invoke-Api GET '/v1/auth/me' -Token $ephemeralAccess
Assert-Step 'revoked device access token rejected' ($meAfterRevoke.Status -eq 401) "status=$($meAfterRevoke.Status)"

$refAfter = Invoke-Api POST '/v1/auth/token/refresh' @{
    refresh_token   = $ephemeralRefresh
    device_id       = $ephemeralDeviceId
    installation_id = $ephemeralInstall
}
Assert-Step 'revoked device refresh rejected' ($refAfter.Status -in 401, 403) "status=$($refAfter.Status)"

$meKeep = Invoke-Api GET '/v1/auth/me' -Token $keepAccess
Assert-Step 'other active session still valid' ($meKeep.Status -eq 200 -and $meKeep.Json.ok) "status=$($meKeep.Status)"

if ($failed -gt 0) {
    Write-Host "`nFAILED=$failed" -ForegroundColor Red
    exit 1
}
Write-Host "`nAll RAP-P0-01 acceptance checks passed." -ForegroundColor Green
exit 0
