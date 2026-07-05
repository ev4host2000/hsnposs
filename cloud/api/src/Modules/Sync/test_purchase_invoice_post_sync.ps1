#Requires -Version 5.1
param([string]$BaseUrl = 'http://127.0.0.1:8787')

$companyId = '550e8400-e29b-41d4-a716-446655440000'
$branchId = '660e8400-e29b-41d4-a716-446655440001'
$deviceId = '770e8400-e29b-41d4-a716-446655440002'
$installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
$userId = '990e8400-e29b-41d4-a716-446655440004'
$productId = 'a100e840-e29b-41d4-a716-446655440020'
$supplierId = 'd100e840-e29b-41d4-a716-446655440050'
$invoiceId = [guid]::NewGuid().ToString()
$lineId = [guid]::NewGuid().ToString()

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
    param([int]$TransactionVersion = 0, [int]$RowVersion = 1)
    return @{
        payload_schema_version = 1
        operation = 'create'
        client_row_version = $RowVersion
        aggregate = @{
            header = @{
                id = $invoiceId
                company_id = $companyId
                branch_id = $branchId
                document_type = 'purchase_invoice'
                status = 'draft'
                transaction_version = $TransactionVersion
                row_version = $RowVersion
                supplier_id = $supplierId
                invoice_date = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
                payment_type = 'cash'
                line_subtotal = 50
                discount_amount = 0
                tax_percent = 0
                total = 50
                paid_amount = 0
                created_by_user_id = $userId
            }
            lines = @(@{
                line_id = $lineId
                product_id = $productId
                quantity = 2
                unit_cost = 25
                line_total = 50
            })
            metadata = @{
                payload_schema_version = 1
                origin_device_id = $deviceId
            }
        }
    }
}

function New-PostEnvelope {
    param(
        [string]$MovementId,
        [string]$DrEntryId,
        [string]$CrSupplierId,
        [int]$RowVersion = 2
    )
    $inventory = @(@{
        movement_id = $MovementId
        product_id = $productId
        quantity = 2
        movement_type = 'in'
        reference_type = 'purchase'
        reference_id = $invoiceId
        movement_date = (Get-Date).ToUniversalTime().ToString('o')
        created_by_user_id = $userId
    })
    $accounting = @(
        @{
            entry_id = $DrEntryId
            partner_kind = 'supplier'
            partner_id = $supplierId
            entry_type = 'purchase_post_dr_purchases'
            reference_type = 'purchase'
            reference_id = $invoiceId
            amount_signed = 50
            entry_date = (Get-Date).ToUniversalTime().ToString('o')
            created_by_user_id = $userId
        },
        @{
            entry_id = $CrSupplierId
            partner_kind = 'supplier'
            partner_id = $supplierId
            entry_type = 'purchase_post_cr_supplier'
            reference_type = 'purchase'
            reference_id = $invoiceId
            amount_signed = -50
            entry_date = (Get-Date).ToUniversalTime().ToString('o')
            created_by_user_id = $userId
        }
    )
    return @{
        payload_schema_version = 1
        operation = 'post'
        client_row_version = $RowVersion
        aggregate = @{
            header = @{
                id = $invoiceId
                company_id = $companyId
                branch_id = $branchId
                document_type = 'purchase_invoice'
                status = 'posted'
                transaction_version = 1
                row_version = $RowVersion
                supplier_id = $supplierId
                total = 50
                created_by_user_id = $userId
            }
            lines = @(@{
                line_id = $lineId
                product_id = $productId
                quantity = 2
                unit_cost = 25
                line_total = 50
            })
            inventory = $inventory
            accounting = $accounting
            metadata = @{
                payload_schema_version = 1
                origin_device_id = $deviceId
                inventory = $inventory
                accounting = $accounting
            }
        }
    }
}

Write-Host '=== Purchase Invoice Post Sync Test ===' -ForegroundColor Cyan
$token = Get-Token
$auth = @{ Authorization = "Bearer $token" }

# Ensure supplier exists
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
            credit_limit = 0
        }
    })
}
Write-Host "Customer push: $($custPush.Status)"

$draftPush = Invoke-Api -Method POST -Path '/v1/sync/push/purchase-invoices' -Headers $auth -Body @{
    company_id = $companyId
    branch_id = $branchId
    device_id = $deviceId
    batch_id = [guid]::NewGuid().ToString()
    events = @(@{
        outbox_id = [guid]::NewGuid().ToString()
        entity_type = 'purchase_invoice'
        entity_id = $invoiceId
        operation = 'create'
        client_row_version = 1
        idempotency_key = "$deviceId`:$invoiceId`:create:test"
        payload_json = (New-DraftEnvelope)
    })
}
Write-Host "Draft push: $($draftPush.Status) $($draftPush.Raw)"
if ($draftPush.Status -ge 400) { exit 1 }

$movementId = [guid]::NewGuid().ToString()
$drId = [guid]::NewGuid().ToString()
$crId = [guid]::NewGuid().ToString()
$postPush = Invoke-Api -Method POST -Path '/v1/sync/push/purchase-invoices' -Headers $auth -Body @{
    company_id = $companyId
    branch_id = $branchId
    device_id = $deviceId
    batch_id = [guid]::NewGuid().ToString()
    events = @(@{
        outbox_id = [guid]::NewGuid().ToString()
        entity_type = 'purchase_invoice'
        entity_id = $invoiceId
        operation = 'post'
        client_row_version = 2
        idempotency_key = "$deviceId`:$invoiceId`:post"
        payload_json = (New-PostEnvelope -MovementId $movementId -DrEntryId $drId -CrSupplierId $crId)
    })
}
Write-Host "Post push: $($postPush.Status) $($postPush.Raw)"
if ($postPush.Status -ge 400) { exit 1 }

$postPush2 = Invoke-Api -Method POST -Path '/v1/sync/push/purchase-invoices' -Headers $auth -Body @{
    company_id = $companyId
    branch_id = $branchId
    device_id = $deviceId
    batch_id = [guid]::NewGuid().ToString()
    events = @(@{
        outbox_id = [guid]::NewGuid().ToString()
        entity_type = 'purchase_invoice'
        entity_id = $invoiceId
        operation = 'post'
        client_row_version = 2
        idempotency_key = "$deviceId`:$invoiceId`:post"
        payload_json = (New-PostEnvelope -MovementId $movementId -DrEntryId $drId -CrSupplierId $crId)
    })
}
Write-Host "Post replay: $($postPush2.Status) accepted=$($postPush2.Json.data.accepted) duplicates=$($postPush2.Json.data.duplicates)"

Write-Host 'PASS' -ForegroundColor Green
