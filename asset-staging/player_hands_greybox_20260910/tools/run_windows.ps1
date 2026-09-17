param(
    [Parameter(Mandatory = $true)][string]$BlenderPath,
    [string]$InputDirectory = (Join-Path $PSScriptRoot '..\input'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot ('..\windows_output\greybox_' + (Get-Date -Format 'yyyyMMdd_HHmmss')))
)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This launcher performs production Blender work only on Windows.'
}
if (-not (Test-Path -LiteralPath $BlenderPath -PathType Leaf)) {
    throw "Blender executable not found: $BlenderPath"
}
$BlenderPath = (Resolve-Path -LiteralPath $BlenderPath).Path
$InputDirectory = (Resolve-Path -LiteralPath $InputDirectory).Path
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) {
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        throw "Output path is a file: $OutputDirectory"
    }
    if (@(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count -gt 0) {
        throw "Refusing nonempty output directory: $OutputDirectory"
    }
}
$BuilderPath = Join-Path $PSScriptRoot 'build_hands_greybox_windows.py'
# Keep logs outside the output folder so the Python builder can enforce emptiness.
$LogDirectory = Join-Path $PSScriptRoot '..\windows_logs'
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$StdoutPath = Join-Path $LogDirectory "$Stamp.stdout.log"
$StderrPath = Join-Path $LogDirectory "$Stamp.stderr.log"
function Quote-Argument([string]$Value) {
    if ($Value.Contains('"')) { throw 'Double quotes in paths are unsupported.' }
    return '"' + $Value + '"'
}
$Arguments = @('--background', '--factory-startup', '--python-exit-code', '1',
    '--python', (Quote-Argument $BuilderPath), '--',
    '--input-dir', (Quote-Argument $InputDirectory),
    '--output-dir', (Quote-Argument $OutputDirectory))
Write-Host "Windows Blender: $BlenderPath"
Write-Host "Input: $InputDirectory"
Write-Host "New output: $OutputDirectory"
$Process = Start-Process -FilePath $BlenderPath -ArgumentList $Arguments -PassThru `
    -WindowStyle Hidden -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
try { $Process.PriorityClass = 'BelowNormal' } catch { Write-Warning 'Could not lower Blender priority.' }
$Process.WaitForExit()
$Process.Refresh()
if ($Process.ExitCode -ne 0) {
    throw "Blender failed ($($Process.ExitCode)). Inspect $StdoutPath and $StderrPath; use a NEW output path to retry."
}
$ReportPath = Join-Path $OutputDirectory 'build_report.json'
if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
    throw "Blender exited without a successful build report. Inspect $StdoutPath and $StderrPath."
}
$Report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
if ($Report.host.system -ne 'Windows' -or -not $Report.host.background) {
    throw 'Report does not attest to Windows background production.'
}
Write-Host "Built: $OutputDirectory"
Write-Host 'Pending: render inspection, GLB reimport verification, and Godot integration/test-room checks.'
Write-Host "Build report: $ReportPath"
