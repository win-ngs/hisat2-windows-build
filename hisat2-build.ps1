$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$ScriptArgs = @($args | ForEach-Object { [string]$_ })
$ScriptDir = $PSScriptRoot
$AppDir = Join-Path -Path $ScriptDir -ChildPath 'hisat2-2.2.2-patch'
if (-not (Test-Path -LiteralPath $AppDir -PathType Container)) {
    $AppDir = $ScriptDir
}

$BuildBinS = Join-Path -Path $AppDir -ChildPath 'hisat2-build-s.exe'
$BuildBinL = Join-Path -Path $AppDir -ChildPath 'hisat2-build-l.exe'
$BuildBinName = 'hisat2-build'
$BigIndexThreshold = 4GB - 200
$DebugMode = $false
$LargeIndex = $false
$VerboseMode = $false
$ForwardArgs = New-Object System.Collections.Generic.List[string]

function Write-Info {
    param([string]$Message)
    if ($script:VerboseMode) {
        [Console]::Error.Write($Message + "`n")
    }
}

function Fail {
    param([string]$Message)
    [Console]::Error.Write($Message + "`n")
    exit 1
}

function Add-DebugSuffix {
    param([string]$Path)
    if ($Path.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring(0, $Path.Length - 4) + '-debug.exe'
    }
    return $Path + '-debug'
}

for ($i = 0; $i -lt $ScriptArgs.Count; $i++) {
    $Arg = $ScriptArgs[$i]
    switch ($Arg) {
        '--large-index' { $LargeIndex = $true; continue }
        '--debug' { $DebugMode = $true; continue }
        '--verbose' { $VerboseMode = $true; continue }
        default { $ForwardArgs.Add($Arg) }
    }
}

$BuildBin = $BuildBinS
if ($LargeIndex) {
    Write-Info('Using large index because --large-index is present.')
    $BuildBin = $BuildBinL
} elseif ($ForwardArgs.Count -ge 2) {
    $ReferenceNames = $ForwardArgs[$ForwardArgs.Count - 2]
    $Size = [int64]0
    foreach ($ReferenceName in ($ReferenceNames -split ',')) {
        if (Test-Path -LiteralPath $ReferenceName -PathType Leaf) {
            $Size += (Get-Item -LiteralPath $ReferenceName).Length
        }
    }

    if ($Size -gt $BigIndexThreshold) {
        Write-Info('Using large index because reference input is larger than the small-index limit.')
        $BuildBin = $BuildBinL
    }
}

if ($DebugMode) {
    $BuildBin = Add-DebugSuffix $BuildBin
}

if (-not (Test-Path -LiteralPath $BuildBin -PathType Leaf)) {
    Fail("Could not find executable: $BuildBin")
}

$NativeArgs = @('--wrapper', 'basic-0') + @($ForwardArgs)
Write-Info("$BuildBinName wrapper: invoking $BuildBin")
& $BuildBin @NativeArgs
exit $LASTEXITCODE
