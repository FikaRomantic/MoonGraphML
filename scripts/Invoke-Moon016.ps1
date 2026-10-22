# Project-local workaround for the 2026-10-16 Windows drive-path regression.
# It runs the installed moon/moonc, preserves exit codes and never edits them.
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$MoonArgs)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$moonCommand = (Get-Command moon -CommandType Application -ErrorAction Stop).Source
$realCompiler = Join-Path (Split-Path -Parent $moonCommand) 'moonc.exe'
$version = (& $moonCommand version --all | Out-String)
if ($LASTEXITCODE -ne 0 -or $version -notmatch '(?m)^moonc v0\.10\.16(?:\+|\s)') {
    throw 'This workaround is restricted to moonc v0.10.16; use normal moon commands for other versions.'
}
if (-not $MoonArgs -or $MoonArgs.Count -eq 0) { $MoonArgs = @('version', '--all') }
$compilerDriver = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compilerDriver)) {
    throw 'Windows .NET Framework C# compiler is required for this local adapter.'
}
$adapterDirectory = Join-Path $projectRoot '.local\toolchain-016'
New-Item -ItemType Directory -Path $adapterDirectory -Force | Out-Null
$adapterSource = Join-Path $PSScriptRoot 'windows_moonc_adapter.cs'
$adapterExecutable = Join-Path $adapterDirectory 'moonc-path-adapter.exe'
$formatterAdapter = Join-Path $adapterDirectory 'moonfmt-path-adapter.exe'
& $compilerDriver /nologo /target:exe "/out:$adapterExecutable" $adapterSource
if ($LASTEXITCODE -ne 0) { throw 'Could not compile the project-local path adapter.' }
Copy-Item -LiteralPath $adapterExecutable -Destination $formatterAdapter -Force
$previousOverride = $env:MOONC_OVERRIDE
$previousCompiler = $env:MOONGRAPHML_REAL_COMPILER
$previousFormatterOverride = $env:MOONFMT_OVERRIDE
$previousFormatter = $env:MOONGRAPHML_REAL_FORMATTER
try {
    $env:MOONC_OVERRIDE = $adapterExecutable
    $env:MOONGRAPHML_REAL_COMPILER = $realCompiler
    $env:MOONFMT_OVERRIDE = $formatterAdapter
    $env:MOONGRAPHML_REAL_FORMATTER = Join-Path (Split-Path -Parent $moonCommand) 'moonfmt.exe'
    & $moonCommand @MoonArgs
    $resultCode = $LASTEXITCODE
} finally {
    $env:MOONC_OVERRIDE = $previousOverride
    $env:MOONGRAPHML_REAL_COMPILER = $previousCompiler
    $env:MOONFMT_OVERRIDE = $previousFormatterOverride
    $env:MOONGRAPHML_REAL_FORMATTER = $previousFormatter
}
exit $resultCode
