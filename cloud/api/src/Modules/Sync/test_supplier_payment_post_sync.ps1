#Requires -Version 5.1
param([string]$BaseUrl = 'http://127.0.0.1:8787')

$companyId = '550e8400-e29b-41d4-a716-446655440000'
$branchId = '660e8400-e29b-41d4-a716-446655440001'
$deviceId = '770e8400-e29b-41d4-a716-446655440002'
$installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
$userId = '990e8400-e29b-41d4-a716-446655440004'
$supplierId = 'd100e840-e29b-41d4-a716-446655440099'
$paymentId = [guid]::NewGuid().ToString()

function Invoke-Api {
    param([string]$Method, [string]$Path, [hashtable]$Body = $null, [hashtable]$Headers = @{})
    $params = @{
        Uri = "$BaseUrl$Path"
        Method = $Method
        Headers = @{ 'Content-Type' = 'application/json' } + $Headers
    }
    if ($Body) { $params['Body'] = ($Body | ConvertTo-Json -Depth 20) }
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

function Get-Token {
    $login = Invoke-Api -Method POST -Path '/v1/auth/login' -Body @{
        username = 'owner@store.com'
        password = 'MizaTest123!'
        company_id = $companyId
        branch_id = $branchId
        device_id = $deviceId
        installation_id = $installationId
    }
    if ($login.Status -ne 200) { throw "Login failed: $($login.Raw)" }
    return $login.Json.data.access_token
}

function New-DraftEnvelope {
    param([int]$TransactionVersion = 0, [int]$RowVersion = 1, [double]$Amount = 100)
    return @{
        payload_schema_version = 1
        operation = 'create'
        client_row_version = $RowVersion
        aggregate = @{
            header = @{
                id = $paymentId
                company_id = $companyId
                branch_id = $branchId
                document_type = 'supplier_payment'
                status = 'draft'
                transaction_version = $TransactionVersion
                row_version = $RowVersion
                supplier_id = $supplierId
                amount = $Amount
                payment_date = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
                payment_method = 'cash'
                created_by_user_id = $userId
            }
            lines = @()
            metadata = @{
                payload_schema_version = 1
                origin_device_id = $deviceId
            }
        }
    }
}

function New-PostEnvelope {
    param(
        [string]$CashTxnId,
        [string]$LedgerEntryId,
        [int]$RowVersion = 2,
        [double]$Amount = 100
    )
    $accounting = @(@{
        entry_id = $LedgerEntryId
        partner_kind = 'supplier'
        partner_id = $supplierId
        entry_type = 'supplier_payment'
        reference_type = 'supplier_payment'
        reference_id = $paymentId
        amount_signed = -$Amount
        entry_date = (Get-Date).ToUniversalTime().ToString('o')
        created_by_user_id = $userId
    })
    $cash = @(@{
        transaction_id = $CashTxnId
        transaction_type = 'out'
        amount = $Amount
        description = 'Supplier payment'
        reference_type = 'supplier_payment'
        reference_id = $paymentId
        transaction_date = (Get-Date).ToUniversalTime().ToString('o')
        created_by_user_id = $userId
    })
    return @{
        payload_schema_version = 1
        operation = 'post'
        client_row_version = $RowVersion
        aggregate = @{
            header = @{
                id = $paymentId
                company_id = $companyId
                branch_id = $branchId
                document_type = 'supplier_payment'
                status = 'posted'
                transaction_version = 1
                row_version = $RowVersion
                supplier_id = $supplierId
                amount = $Amount
                created_by_user_id = $userId
            }
            lines = @()
            accounting = $accounting
            cash = $cash
            metadata = @{
                payload_schema_version = 1
                origin_device_id = $deviceId
                accounting = $accounting
                cash = $cash
            }
        }
    }
}

Write-Host '=== Supplier Payment Post Sync Test ===' -ForegroundColor Cyan
$token = Get-Token
$auth = @{ Authorization = "Bearer $token" }

$supPush = Invoke-Api -Method POST -Path '/v1/sync/push/suppliers' -Headers $auth -Body @{
    company_id = $companyId
    branch_id = $branchId
    device_id = $deviceId
    batch_id = [guid]::NewGuid().ToString()
    events = @(@{
        outbox_id = [guid]::NewGuid().ToString()
        entity_type = 'supplier'
        entity_id = $supplierId
        operation = 'create'
        client_row_version = 1
        idempotency_key = "$deviceId`:$supplierId`:create:test"
        payload_json = @{
            id = $supplierId
            company_id = $companyId
            branch_id = $branchId
            name = 'Post Test Supplier'
        }
    })
}
Write-Host "Supplier push: $($supPush.Status)"

$draftPush = Invoke-Api -Method POST -Path '/v1/sync/push/supplier-payments' -Headers $auth -Body @{
    company_id = $companyId
    branch_id = $branchId
    device_id = $deviceId
    batch_id = [guid]::NewGuid().ToString()
    events = @(@{
        outbox_id = [guid]::NewGuid().ToString()
        entity_type = 'supplier_payment'
        entity_id = $paymentId
        operation = 'create'
        client_row_version = 1
        idempotency_key = "$deviceId`:$paymentId`:create:test"
        payload_json = (New-DraftEnvelope)
    })
}
Write-Host "Draft push: $($draftPush.Status) $($draftPush.Raw)"
if ($draftPush.Status -ge 400) { exit 1 }

$cashId = [guid]::NewGuid().ToString()
$ledgerId = [guid]::NewGuid().ToString()
$postPush = Invoke-Api -Method POST -Path '/v1/sync/push/supplier-payments' -Headers $auth -Body @{
    company_id = $companyId
    branch_id = $branchId
    device_id = $deviceId
    batch_id = [guid]::NewGuid().ToString()
    events = @(@{
        outbox_id = [guid]::NewGuid().ToString()
        entity_type = 'supplier_payment'
        entity_id = $paymentId
        operation = 'post'
        client_row_version = 2
        idempotency_key = "$deviceId`:$paymentId`:post"
        payload_json = (New-PostEnvelope -CashTxnId $cashId -LedgerEntryId $ledgerId)
    })
}
Write-Host "Post push: $($postPush.Status) $($postPush.Raw)"
if ($postPush.Status -ge 400) { exit 1 }

$postPush2 = Invoke-Api -Method POST -Path '/v1/sync/push/supplier-payments' -Headers $auth -Body @{
    company_id = $companyId
    branch_id = $branchId
    device_id = $deviceId
    batch_id = [guid]::NewGuid().ToString()
    events = @(@{
        outbox_id = [guid]::NewGuid().ToString()
        entity_type = 'supplier_payment'
        entity_id = $paymentId
        operation = 'post'
        client_row_version = 2
        idempotency_key = "$deviceId`:$paymentId`:post"
        payload_json = (New-PostEnvelope -CashTxnId $cashId -LedgerEntryId $ledgerId)
    })
}
Write-Host "Post replay: $($postPush2.Status) accepted=$($postPush2.Json.data.accepted) duplicates=$($postPush2.Json.data.duplicates)"

Write-Host 'PASS' -ForegroundColor Green
