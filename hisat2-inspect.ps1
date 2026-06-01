$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$ScriptArgs = @($args | ForEach-Object { [string]$_ })
$ScriptDir = $PSScriptRoot
$AppDir = Join-Path -Path $ScriptDir -ChildPath 'hisat2-2.2.2-patch'
if (-not (Test-Path -LiteralPath $AppDir -PathType Container)) {
    $AppDir = $ScriptDir
}

$InspectBinS = Join-Path -Path $AppDir -ChildPath 'hisat2-inspect-s.exe'
$InspectBinL = Join-Path -Path $AppDir -ChildPath 'hisat2-inspect-l.exe'
$InspectBinName = 'hisat2-inspect'
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

function Test-IndexPart {
    param(
        [string]$BaseName,
        [string]$Extension
    )
    return (Test-Path -LiteralPath ($BaseName + ".1.$Extension") -PathType Leaf)
}

function Test-IndexPartFromEnv {
    param(
        [string]$BaseName,
        [string]$Extension
    )
    if ([string]::IsNullOrEmpty($env:HISAT2_INDEXES)) {
        return $false
    }
    $Candidate = Join-Path -Path $env:HISAT2_INDEXES -ChildPath ($BaseName + ".1.$Extension")
    return (Test-Path -LiteralPath $Candidate -PathType Leaf)
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

$InspectBin = $InspectBinS
if ($LargeIndex) {
    Write-Info('Using large index because --large-index is present.')
    $InspectBin = $InspectBinL
} elseif ($ForwardArgs.Count -ge 1) {
    $IndexName = $ForwardArgs[$ForwardArgs.Count - 1]
    $LargeExists = (Test-IndexPart $IndexName 'ht2l') -or (Test-IndexPartFromEnv $IndexName 'ht2l')
    $SmallExists = (Test-IndexPart $IndexName 'ht2') -or (Test-IndexPartFromEnv $IndexName 'ht2')
    if ($LargeExists -and -not $SmallExists) {
        Write-Info('Using large index because only .ht2l files were found.')
        $InspectBin = $InspectBinL
    }
}

if ($DebugMode) {
    $InspectBin = Add-DebugSuffix $InspectBin
}

if (-not (Test-Path -LiteralPath $InspectBin -PathType Leaf)) {
    Fail("Could not find executable: $InspectBin")
}

$NativeArgs = @('--wrapper', 'basic-0') + @($ForwardArgs)
Write-Info("$InspectBinName wrapper: invoking $InspectBin")
& $InspectBin @NativeArgs
exit $LASTEXITCODE
