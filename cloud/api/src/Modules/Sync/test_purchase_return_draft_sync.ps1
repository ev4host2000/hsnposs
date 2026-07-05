#Requires -Version 5.1
param([string]$BaseUrl = 'http://127.0.0.1:8787')

$companyId = '550e8400-e29b-41d4-a716-446655440000'
$branchId = '660e8400-e29b-41d4-a716-446655440001'
$deviceId = '770e8400-e29b-41d4-a716-446655440002'
$installationId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
$userId = '990e8400-e29b-41d4-a716-446655440004'
$productId = 'a100e840-e29b-41d4-a716-446655440020'
$supplierId = 'd100e840-e29b-41d4-a716-446655440050'
$originalInvoiceId = [guid]::NewGuid().ToString()
$returnId = [guid]::NewGuid().ToString()
$lineId = [guid]::NewGuid().ToString()
$origLineId = [guid]::NewGuid().ToString()

function Invoke-Api {
    param([string]$Method, [string]$Path, [hashtable]$Body = $null, [hashtable]$Headers = @{})
    $params = @{
        Uri = "$BaseUrl$Path"
        Method = $Method
        Headers = @{ 'Content-Type' = 'application/json' } + $Headers
    }
    if ($Body) { $params['Body'] = ($Body | ConvertTo-Json -Depth 12) }
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

function New-AggregateEnvelope {
    param(
        [string]$Operation,
        [int]$TransactionVersion = 0,
        [int]$RowVersion = 1,
        [string]$Status = 'draft',
        [string]$Notes = 'Draft v1',
        [double]$Total = 50
    )
    return @{
        payload_schema_version = 1
        operation = $Operation
        client_row_version = $RowVersion
        aggregate = @{
            header = @{
                id = $returnId
                company_id = $companyId
                branch_id = $branchId
                document_type = 'purchase_return'
                status = $Status
                transaction_version = $TransactionVersion
                row_version = $RowVersion
                original_invoice_id = $originalInvoiceId
                supplier_id = $supplierId
                return_date = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
                payment_type = 'cash'
                line_subtotal = $Total
                discount_amount = 0
                tax_percent = 0
                total = $Total
                paid_amount = 0
                notes = $Notes
                created_by_user_id = $userId
            }
            lines = @(@{
                line_id = $lineId
                product_id = $productId
                quantity = 2
                unit_cost = ($Total / 2)
                line_total = $Total
            })
            metadata = @{
                payload_schema_version = 1
                origin_device_id = $deviceId
            }
        }
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
    registered_by_user_id = $userId
} @{ Authorization = "Bearer $userToken"; 'X-Company-ID' = $companyId; 'X-Branch-ID' = $branchId }
$deviceToken = $reg.Json.data.access_token
$headers = @{
    Authorization = "Bearer $deviceToken"
    'X-Device-ID' = $deviceId
    'X-Company-ID' = $companyId
    'X-Branch-ID' = $branchId
}

Write-Host 'Seed original purchase invoice (FK parent)' -ForegroundColor Cyan
$origPush = Invoke-Api POST '/v1/sync/push/purchase-invoices' @{
    company_id = $companyId; branch_id = $branchId; device_id = $deviceId
    batch_id = [guid]::NewGuid().ToString()
    events = @(@{
        entity_type = 'purchase_invoice'; entity_id = $originalInvoiceId; operation = 'create'
        outbox_id = [guid]::NewGuid().ToString()
        idempotency_key = "$deviceId`:$originalInvoiceId`:create:orig"
        client_row_version = 1
        payload_json = @{
            payload_schema_version = 1; operation = 'create'; client_row_version = 1
            aggregate = @{
                header = @{
                    id = $originalInvoiceId; company_id = $companyId; branch_id = $branchId
                    document_type = 'purchase_invoice'; status = 'draft'
                    supplier_id = $supplierId; invoice_date = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
                    payment_type = 'cash'; line_subtotal = 100; total = 100; created_by_user_id = $userId
                }
                lines = @(@{ line_id = $origLineId; product_id = $productId; quantity = 4; unit_cost = 25; line_total = 100 })
                metadata = @{ payload_schema_version = 1; origin_device_id = $deviceId }
            }
        }
    })
} $headers
if ($origPush.Status -notin 200, 202) { throw "Original invoice push failed: $($origPush.Raw)" }

Write-Host 'Push create draft return' -ForegroundColor Cyan
$batchId = [guid]::NewGuid().ToString()
$createPayload = New-AggregateEnvelope -Operation 'create'
$pushCreate = Invoke-Api POST '/v1/sync/push/purchase-returns' @{
    company_id = $companyId; branch_id = $branchId; device_id = $deviceId; batch_id = $batchId
    events = @(@{
        entity_type = 'purchase_return'; entity_id = $returnId; operation = 'create'
        outbox_id = [guid]::NewGuid().ToString()
        idempotency_key = "$deviceId`:$returnId`:create:$batchId"
        client_row_version = 1; payload_json = $createPayload
    })
} $headers
if ($pushCreate.Status -notin 200, 202) { throw "Create push failed: $($pushCreate.Raw)" }

Write-Host 'Pull Purchase Returns' -ForegroundColor Cyan
$pull = Invoke-Api GET "/v1/sync/pull/purchase-returns?company_id=$companyId&branch_id=$branchId&since_sequence=0&limit=50" $null $headers
if ($pull.Status -ne 200) { throw "Pull failed: $($pull.Raw)" }
if (-not $pull.Json.data.entries -or $pull.Json.data.entries.Count -lt 1) {
    throw 'Pull returned no entries'
}
Write-Host "  OK create - entries=$($pull.Json.data.entries.Count), has_more=$($pull.Json.meta.has_more)" -ForegroundColor Green

Write-Host 'Push update draft return' -ForegroundColor Cyan
$batchId2 = [guid]::NewGuid().ToString()
$updatePayload = New-AggregateEnvelope -Operation 'update' -TransactionVersion 1 -RowVersion 2 -Notes 'Draft v2' -Total 80
$pushUpdate = Invoke-Api POST '/v1/sync/push/purchase-returns' @{
    company_id = $companyId; branch_id = $branchId; device_id = $deviceId; batch_id = $batchId2
    events = @(@{
        entity_type = 'purchase_return'; entity_id = $returnId; operation = 'update'
        outbox_id = [guid]::NewGuid().ToString()
        idempotency_key = "$deviceId`:$returnId`:update:$batchId2"
        client_row_version = 2; payload_json = $updatePayload
    })
} $headers
if ($pushUpdate.Status -notin 200, 202) { throw "Update push failed: $($pushUpdate.Raw)" }

Write-Host 'Push cancel draft return' -ForegroundColor Cyan
$batchId3 = [guid]::NewGuid().ToString()
$cancelPayload = New-AggregateEnvelope -Operation 'cancel' -TransactionVersion 1 -RowVersion 3 -Status 'cancelled' -Notes 'Deleted'
$pushCancel = Invoke-Api POST '/v1/sync/push/purchase-returns' @{
    company_id = $companyId; branch_id = $branchId; device_id = $deviceId; batch_id = $batchId3
    events = @(@{
        entity_type = 'purchase_return'; entity_id = $returnId; operation = 'cancel'
        outbox_id = [guid]::NewGuid().ToString()
        idempotency_key = "$deviceId`:$returnId`:cancel:$batchId3"
        client_row_version = 3; payload_json = $cancelPayload
    })
} $headers
if ($pushCancel.Status -notin 200, 202) { throw "Cancel push failed: $($pushCancel.Raw)" }

Write-Host 'Purchase Return draft sync OK' -ForegroundColor Green
