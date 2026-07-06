#Requires -Version 5.1
param([string]$BaseUrl = 'http://127.0.0.1:8787')

$companyId = '550e8400-e29b-41d4-a716-446655440000'
$branchId = '660e8400-e29b-41d4-a716-446655440001'
$deviceId = '770e8400-e29b-41d4-a716-446655440002'
$installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
$userId = '990e8400-e29b-41d4-a716-446655440004'
$productId = 'a100e840-e29b-41d4-a716-446655440020'
$adjustmentId = [guid]::NewGuid().ToString()

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
    param([int]$TransactionVersion = 0, [int]$RowVersion = 1, [double]$QuantityDelta = 5)
    return @{
        payload_schema_version = 1
        operation = 'create'
        client_row_version = $RowVersion
        aggregate = @{
            header = @{
                id = $adjustmentId
                company_id = $companyId
                branch_id = $branchId
                document_type = 'inventory_adjustment'
                status = 'draft'
                transaction_version = $TransactionVersion
                row_version = $RowVersion
                product_id = $productId
                quantity_delta = $QuantityDelta
                adjustment_date = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
                adjustment_reason = 'count'
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
        [string]$MovementId,
        [int]$RowVersion = 2,
        [double]$QuantityDelta = 5
    )
    $inventory = @(@{
        movement_id = $MovementId
        product_id = $productId
        quantity = $QuantityDelta
        movement_type = 'in'
        reference_type = 'inventory_adjustment'
        reference_id = $adjustmentId
        movement_date = (Get-Date).ToUniversalTime().ToString('o')
        created_by_user_id = $userId
    })
    return @{
        payload_schema_version = 1
        operation = 'post'
        client_row_version = $RowVersion
        aggregate = @{
            header = @{
                id = $adjustmentId
                company_id = $companyId
                branch_id = $branchId
                document_type = 'inventory_adjustment'
                status = 'posted'
                transaction_version = 1
                row_version = $RowVersion
                product_id = $productId
                quantity_delta = $QuantityDelta
                created_by_user_id = $userId
            }
            lines = @()
            inventory = $inventory
            metadata = @{
                payload_schema_version = 1
                origin_device_id = $deviceId
                inventory = $inventory
            }
        }
    }
}

Write-Host '=== Inventory Adjustment Post Sync Test ===' -ForegroundColor Cyan
$token = Get-Token
$auth = @{ Authorization = "Bearer $token" }

$prodPush = Invoke-Api -Method POST -Path '/v1/sync/push/products' -Headers $auth -Body @{
    company_id = $companyId
    branch_id = $branchId
    device_id = $deviceId
    batch_id = [guid]::NewGuid().ToString()
    events = @(@{
        outbox_id = [guid]::NewGuid().ToString()
        entity_type = 'product'
        entity_id = $productId
        operation = 'create'
        client_row_version = 1
        idempotency_key = "$deviceId`:$productId`:create:adj-post"
        payload_json = @{
            id = $productId
            company_id = $companyId
            branch_id = $branchId
            name = 'Post Test Product'
            sku = 'ADJ-POST-001'
            stock_qty = 10
            sale_price = 25
        }
    })
}
Write-Host "Product push: $($prodPush.Status)"
if ($prodPush.Status -ge 400) { exit 1 }

$draftPush = Invoke-Api -Method POST -Path '/v1/sync/push/inventory-adjustments' -Headers $auth -Body @{
    company_id = $companyId
    branch_id = $branchId
    device_id = $deviceId
    batch_id = [guid]::NewGuid().ToString()
    events = @(@{
        outbox_id = [guid]::NewGuid().ToString()
        entity_type = 'inventory_adjustment'
        entity_id = $adjustmentId
        operation = 'create'
        client_row_version = 1
        idempotency_key = "$deviceId`:$adjustmentId`:create:test"
        payload_json = (New-DraftEnvelope)
    })
}
Write-Host "Draft push: $($draftPush.Status) $($draftPush.Raw)"
if ($draftPush.Status -ge 400) { exit 1 }

$movementId = [guid]::NewGuid().ToString()
$postPush = Invoke-Api -Method POST -Path '/v1/sync/push/inventory-adjustments' -Headers $auth -Body @{
    company_id = $companyId
    branch_id = $branchId
    device_id = $deviceId
    batch_id = [guid]::NewGuid().ToString()
    events = @(@{
        outbox_id = [guid]::NewGuid().ToString()
        entity_type = 'inventory_adjustment'
        entity_id = $adjustmentId
        operation = 'post'
        client_row_version = 2
        idempotency_key = "$deviceId`:$adjustmentId`:post"
        payload_json = (New-PostEnvelope -MovementId $movementId)
    })
}
Write-Host "Post push: $($postPush.Status) $($postPush.Raw)"
if ($postPush.Status -ge 400) { exit 1 }

$postPush2 = Invoke-Api -Method POST -Path '/v1/sync/push/inventory-adjustments' -Headers $auth -Body @{
    company_id = $companyId
    branch_id = $branchId
    device_id = $deviceId
    batch_id = [guid]::NewGuid().ToString()
    events = @(@{
        outbox_id = [guid]::NewGuid().ToString()
        entity_type = 'inventory_adjustment'
        entity_id = $adjustmentId
        operation = 'post'
        client_row_version = 2
        idempotency_key = "$deviceId`:$adjustmentId`:post"
        payload_json = (New-PostEnvelope -MovementId $movementId)
    })
}
Write-Host "Post replay: $($postPush2.Status) accepted=$($postPush2.Json.data.accepted) duplicates=$($postPush2.Json.data.duplicates)"

Write-Host 'PASS' -ForegroundColor Green
