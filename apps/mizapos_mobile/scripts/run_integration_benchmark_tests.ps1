#Requires -Version 5.1
<#
.SYNOPSIS
    Runs live integration + benchmark tests serially against the dev cloud tenant.
#>
$ErrorActionPreference = 'Stop'
$mobileRoot = Split-Path $PSScriptRoot -Parent

function Stop-LingeringFlutterTestProcesses {
    Get-Process -Name flutter_tester, dart, flutter, dartaotruntime -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

Push-Location $mobileRoot
try {
    Stop-LingeringFlutterTestProcesses

    $files = @(
        Get-ChildItem test -Filter '*integration_test.dart' | Sort-Object Name | ForEach-Object { $_.FullName }
        Get-ChildItem test -Filter '*benchmark_test.dart' | Sort-Object Name | ForEach-Object { $_.FullName }
    )
    Write-Host "Running $($files.Count) integration/benchmark tests with -j 1 ..."
    flutter test @files -j 1
    $exitCode = $LASTEXITCODE
}
finally {
    Stop-LingeringFlutterTestProcesses
    Pop-Location
}
exit $exitCode
