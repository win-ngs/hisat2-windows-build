$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$ScriptArgs = @($args | ForEach-Object { [string]$_ })
$ScriptDir = $PSScriptRoot
$AppDir = Join-Path -Path $ScriptDir -ChildPath 'hisat2-2.2.2-patch'
if (-not (Test-Path -LiteralPath $AppDir -PathType Container)) {
    $AppDir = $ScriptDir
}

$AlignProgS = Join-Path -Path $AppDir -ChildPath 'hisat2-align-s.exe'
$AlignProgL = Join-Path -Path $AppDir -ChildPath 'hisat2-align-l.exe'
$AlignProg = $AlignProgS
$BuildScript = Join-Path -Path $ScriptDir -ChildPath 'hisat2-build.ps1'
$IndexExtS = 'ht2'
$IndexExtL = 'ht2l'
$IndexExt = $IndexExtS
$SeqInArgs = $false
$SkipReadStat = $false
$DebugMode = $false
$NoUnal = $false
$LargeIndex = $false
$VerboseMode = $false
$KeepTemps = $false
$LogFileName = $null
$TempDir = [System.IO.Path]::GetTempPath()
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$RemovedArgMarker = '__HISAT2_PS1_REMOVED_ARG_6B7041F5E01C4D40__'

function Write-StderrText {
    param([string]$Text)
    if ($script:LogFileName) {
        [System.IO.File]::AppendAllText($script:LogFileName, $Text, $script:Utf8NoBom)
    } else {
        [Console]::Error.Write($Text)
    }
}

function Info {
    param([string]$Message)
    if ($script:VerboseMode) {
        Write-StderrText("(INFO): $Message")
    }
}

function ErrorText {
    param([string]$Message)
    Write-StderrText("(ERR): $Message")
}

function Fail {
    param([string]$Message)
    ErrorText($Message)
    ErrorText("Exiting now ...`n")
    exit 1
}

function Split-CommaValues {
    param([string]$Value)
    if ($null -eq $Value -or $Value.Length -eq 0) {
        return @()
    }
    return @($Value -split ',')
}

function Add-DebugSuffix {
    param([string]$Path)
    if ($Path.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring(0, $Path.Length - 4) + '-debug.exe'
    }
    return $Path + '-debug'
}

function ConvertTo-WindowsProcessArgument {
    param([string]$Argument)
    if ($null -eq $Argument -or $Argument.Length -eq 0) {
        return '""'
    }
    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    $Builder = [System.Text.StringBuilder]::new()
    [void]$Builder.Append('"')
    $Backslashes = 0
    foreach ($Char in $Argument.ToCharArray()) {
        if ($Char -eq '\') {
            $Backslashes++
            continue
        }
        if ($Char -eq '"') {
            [void]$Builder.Append('\' * (($Backslashes * 2) + 1))
            [void]$Builder.Append('"')
            $Backslashes = 0
            continue
        }
        if ($Backslashes -gt 0) {
            [void]$Builder.Append('\' * $Backslashes)
            $Backslashes = 0
        }
        [void]$Builder.Append($Char)
    }
    if ($Backslashes -gt 0) {
        [void]$Builder.Append('\' * ($Backslashes * 2))
    }
    [void]$Builder.Append('"')
    return $Builder.ToString()
}

function Join-WindowsProcessArguments {
    param([string[]]$Arguments)
    $Quoted = New-Object System.Collections.Generic.List[string]
    foreach ($Argument in $Arguments) {
        $Quoted.Add((ConvertTo-WindowsProcessArgument $Argument))
    }
    return ($Quoted -join ' ')
}

function Get-NextValue {
    param(
        [string[]]$Values,
        [ref]$Index,
        [string]$OptionName
    )
    if ($Index.Value -ge $Values.Count - 1) {
        Fail("$OptionName takes an argument.`n")
    }
    $Index.Value++
    return $Values[$Index.Value]
}

function Remove-OptionFromList {
    param(
        [System.Collections.Generic.List[string]]$Values,
        [string[]]$OptionNames,
        [bool]$TakesValue
    )
    for ($i = 0; $i -lt $Values.Count; $i++) {
        if ($null -eq $Values[$i]) {
            continue
        }
        $Parts = $Values[$i] -split '=', 2
        $Option = $Parts[0]
        if ($OptionNames -contains $Option) {
            $Values[$i] = $script:RemovedArgMarker
            if ($TakesValue -and $Parts.Count -eq 1 -and $i -lt $Values.Count - 1) {
                $Values[$i + 1] = $script:RemovedArgMarker
            }
            return
        }
    }
}

function Get-DefinedListValues {
    param([System.Collections.Generic.List[string]]$Values)
    $Result = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $Values.Count; $i++) {
        if ($null -ne $Values[$i] -and $Values[$i] -ne $script:RemovedArgMarker) {
            $Result.Add($Values[$i])
        }
    }
    return [string[]]$Result.ToArray()
}

function Test-ReadWrappingNeeded {
    param([string[]]$Unpaired, [string[]]$Mate1, [string[]]$Mate2)
    foreach ($Name in @($Unpaired + $Mate1 + $Mate2)) {
        if ($Name -match '\.gz$' -or $Name -match '\.bz2$') {
            return $true
        }
    }
    return $false
}

function Check-ReadFilesExist {
    param([string[]]$Unpaired, [string[]]$Mate1, [string[]]$Mate2)
    foreach ($Name in @($Unpaired + $Mate1 + $Mate2)) {
        if ($Name -eq '-') {
            continue
        }
        if (-not (Test-Path -LiteralPath $Name -PathType Leaf)) {
            Fail("Read file '$Name' doesn't exist`n")
        }
    }
}

function New-TempFileName {
    param([string]$Suffix)
    if (-not (Test-Path -LiteralPath $script:TempDir -PathType Container)) {
        New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
    }
    $Leaf = "$PID.$([System.IO.Path]::GetRandomFileName()).$Suffix"
    return (Join-Path -Path $script:TempDir -ChildPath $Leaf)
}

function Copy-ProcessStdoutToStream {
    param(
        [string]$Program,
        [string]$InputFile,
        [System.IO.Stream]$OutputStream
    )
    $Psi = [System.Diagnostics.ProcessStartInfo]::new()
    $Psi.FileName = $Program
    $Psi.UseShellExecute = $false
    $Psi.RedirectStandardOutput = $true
    $Psi.RedirectStandardError = $true
    $Psi.Arguments = Join-WindowsProcessArguments @('-dc', $InputFile)

    $Proc = [System.Diagnostics.Process]::new()
    $Proc.StartInfo = $Psi
    [void]$Proc.Start()
    $Proc.StandardOutput.BaseStream.CopyTo($OutputStream)
    $ErrText = $Proc.StandardError.ReadToEnd()
    $Proc.WaitForExit()
    if ($Proc.ExitCode -ne 0) {
        Fail("$Program failed on '$InputFile': $ErrText`n")
    }
}

function Copy-ReadFileToStream {
    param(
        [string]$InputFile,
        [System.IO.Stream]$OutputStream
    )
    if ($InputFile -eq '-') {
        Fail("Cannot combine stdin with temporary read wrapping on Windows.`n")
    } elseif ($InputFile -match '\.gz$') {
        Copy-ProcessStdoutToStream 'gzip' $InputFile $OutputStream
    } elseif ($InputFile -match '\.bz2$') {
        Copy-ProcessStdoutToStream 'bzip2' $InputFile $OutputStream
    } else {
        $InputStream = [System.IO.File]::OpenRead($InputFile)
        try {
            $InputStream.CopyTo($OutputStream)
        } finally {
            $InputStream.Dispose()
        }
    }
}

function Expand-ReadFilesToTemp {
    param([string[]]$InputFiles, [string]$Suffix)
    $TempFile = New-TempFileName $Suffix
    $OutputStream = [System.IO.File]::Open($TempFile, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
    try {
        foreach ($InputFile in $InputFiles) {
            Copy-ReadFileToStream $InputFile $OutputStream
        }
    } finally {
        $OutputStream.Dispose()
    }
    return $TempFile
}

function Get-ReadFileFormat {
    param([string]$Path)
    $Leaf = [System.IO.Path]::GetFileName($Path)
    $Parts = @($Leaf -split '\.')
    if ($Parts.Count -lt 2) {
        return ''
    }
    $Ext = $Parts[$Parts.Count - 1].ToLowerInvariant()
    if (($Ext -eq 'gz' -or $Ext -eq 'bz2') -and $Parts.Count -ge 3) {
        $Ext = $Parts[$Parts.Count - 2].ToLowerInvariant()
    }
    if ($Ext -in @('fa', 'fasta', 'fna')) {
        return 'fasta'
    }
    if ($Ext -in @('fq', 'fastq')) {
        return 'fastq'
    }
    return ''
}

function Open-ReadTextReader {
    param(
        [string]$Path,
        [System.Collections.Generic.List[object]]$Disposables,
        [System.Collections.Generic.List[object]]$Processes
    )
    $FileStream = [System.IO.File]::OpenRead($Path)
    if ($Path -match '\.gz$') {
        $Disposables.Add($FileStream)
        $GzipStream = [System.IO.Compression.GzipStream]::new($FileStream, [System.IO.Compression.CompressionMode]::Decompress)
        $Disposables.Add($GzipStream)
        $Reader = [System.IO.StreamReader]::new($GzipStream)
    } elseif ($Path -match '\.bz2$') {
        $FileStream.Dispose()
        $Psi = [System.Diagnostics.ProcessStartInfo]::new()
        $Psi.FileName = 'bzip2'
        $Psi.UseShellExecute = $false
        $Psi.RedirectStandardOutput = $true
        $Psi.RedirectStandardError = $true
        $Psi.Arguments = Join-WindowsProcessArguments @('-dc', $Path)
        $Proc = [System.Diagnostics.Process]::new()
        $Proc.StartInfo = $Psi
        [void]$Proc.Start()
        $Processes.Add($Proc)
        $Reader = $Proc.StandardOutput
    } else {
        $Disposables.Add($FileStream)
        $Reader = [System.IO.StreamReader]::new($FileStream)
    }
    $Disposables.Add($Reader)
    return $Reader
}

function Add-ReadLength {
    param([hashtable]$LengthMap, [int]$Length)
    if ($LengthMap.ContainsKey($Length)) {
        $LengthMap[$Length]++
    } else {
        $LengthMap[$Length] = 1
    }
}

function Get-ReadLengthString {
    param([string]$Path, [int]$ReadCount)
    $Format = Get-ReadFileFormat $Path
    if ([string]::IsNullOrEmpty($Format)) {
        return ''
    }

    $LengthMap = @{}
    $Disposables = New-Object System.Collections.Generic.List[object]
    $Processes = New-Object System.Collections.Generic.List[object]
    try {
        $Reader = Open-ReadTextReader $Path $Disposables $Processes
        $Seen = 0
        $Line = $null
        while ($null -ne ($Line = $Reader.ReadLine())) {
            if (($Format -eq 'fasta' -and $Line.StartsWith('>')) -or ($Format -eq 'fastq' -and $Line.StartsWith('@'))) {
                break
            }
        }
        if ($null -eq $Line) {
            return ''
        }

        if ($Format -eq 'fastq') {
            while ($null -ne $Line) {
                $Seq = $Reader.ReadLine()
                if ($null -eq $Seq) {
                    break
                }
                Add-ReadLength $LengthMap $Seq.Trim().Length
                $Seen++
                if ($ReadCount -gt 0 -and $Seen -ge $ReadCount) {
                    break
                }
                [void]$Reader.ReadLine()
                [void]$Reader.ReadLine()
                $Line = $Reader.ReadLine()
            }
        } else {
            while ($null -ne $Line) {
                $SeqLength = 0
                while ($null -ne ($Line = $Reader.ReadLine())) {
                    if ($Line.StartsWith('>')) {
                        break
                    }
                    $SeqLength += $Line.Trim().Length
                }
                Add-ReadLength $LengthMap $SeqLength
                $Seen++
                if ($ReadCount -gt 0 -and $Seen -ge $ReadCount) {
                    break
                }
            }
        }
    } catch {
        Write-StderrText("Warning: $($_.Exception.Message)`n")
        return ''
    } finally {
        for ($i = $Disposables.Count - 1; $i -ge 0; $i--) {
            $Disposables[$i].Dispose()
        }
        foreach ($Proc in $Processes) {
            $ErrText = $Proc.StandardError.ReadToEnd()
            $Proc.WaitForExit()
            if ($Proc.ExitCode -ne 0 -and $ErrText.Length -gt 0) {
                Write-StderrText("Warning: $ErrText`n")
            }
            $Proc.Dispose()
        }
    }

    if ($LengthMap.Count -eq 0) {
        return ''
    }
    $Sorted = $LengthMap.GetEnumerator() | Sort-Object @{ Expression = { $_.Value }; Descending = $true }, @{ Expression = { [int]$_.Key }; Descending = $true }
    return (($Sorted | ForEach-Object { [string]$_.Key }) -join ',')
}

function Test-IndexPart {
    param([string]$BaseName, [string]$Extension)
    return (Test-Path -LiteralPath ($BaseName + ".1.$Extension") -PathType Leaf)
}

function Resolve-IndexBaseName {
    param(
        [string]$BaseName,
        [bool]$RefStringMode
    )
    if ((Test-IndexPart $BaseName $script:IndexExtS) -or (Test-IndexPart $BaseName $script:IndexExtL)) {
        return $BaseName
    }
    if (-not [string]::IsNullOrEmpty($env:HISAT2_INDEXES)) {
        $Candidate = Join-Path -Path $env:HISAT2_INDEXES -ChildPath $BaseName
        if ((Test-IndexPart $Candidate $script:IndexExtS) -or (Test-IndexPart $Candidate $script:IndexExtL)) {
            return $Candidate
        }
    }
    Fail("""$BaseName"" does not exist`n")
}

function Extract-IndexNameFrom {
    param([string[]]$Values, [bool]$RefStringMode)
    $IndexOpt = if ($RefStringMode) { '--index' } else { '-x' }
    for ($i = 0; $i -lt $Values.Count; $i++) {
        $Arg = $Values[$i]
        if ($null -eq $Arg) {
            continue
        }
        if ($Arg -eq $IndexOpt) {
            if ($i -ge $Values.Count - 1) {
                Fail("$IndexOpt takes an argument.`n")
            }
            return (Resolve-IndexBaseName $Values[$i + 1] $RefStringMode)
        }
        if ($IndexOpt -eq '-x' -and $Arg.StartsWith('-x') -and $Arg.Length -gt 2) {
            return (Resolve-IndexBaseName $Arg.Substring(2) $RefStringMode)
        }
        if ($RefStringMode -and $Arg.StartsWith('--index=')) {
            return (Resolve-IndexBaseName $Arg.Substring(8) $RefStringMode)
        }
    }
    Info("Cannot find any index option (--reference-string, --ref-string or -x) in the given command line.`n")
    return $null
}

function New-LfWriter {
    param([string]$Path)
    $Writer = [System.IO.StreamWriter]::new($Path, $false, $script:Utf8NoBom)
    $Writer.NewLine = "`n"
    return $Writer
}

function Get-ReadOutputPaths {
    param([string]$Kind, [string]$Pattern)
    $BaseDir = [System.IO.Path]::GetDirectoryName($Pattern)
    $BaseName = [System.IO.Path]::GetFileName($Pattern)
    if ([string]::IsNullOrEmpty($BaseDir)) {
        $BaseDir = '.'
    }
    if (Test-Path -LiteralPath $Pattern -PathType Container) {
        $BaseDir = $Pattern
        $BaseName = $null
    }

    if ($Kind -match '-conc$' -or $Kind -match '-conc-disc$') {
        if ([string]::IsNullOrEmpty($BaseName)) {
            $File1 = "$Kind-mate.1"
            $File2 = "$Kind-mate.2"
        } elseif ($BaseName.Contains('%')) {
            $File1 = $BaseName.Replace('%', '1')
            $File2 = $BaseName.Replace('%', '2')
        } else {
            $Ext = [System.IO.Path]::GetExtension($BaseName)
            if ($Ext.Length -gt 0) {
                $Stem = $BaseName.Substring(0, $BaseName.Length - $Ext.Length)
                $File1 = "$Stem.1$Ext"
                $File2 = "$Stem.2$Ext"
            } else {
                $File1 = "$BaseName.1"
                $File2 = "$BaseName.2"
            }
        }
        return @((Join-Path -Path $BaseDir -ChildPath $File1), (Join-Path -Path $BaseDir -ChildPath $File2))
    }

    if ([string]::IsNullOrEmpty($BaseName)) {
        return @((Join-Path -Path $BaseDir -ChildPath "$Kind-seqs"))
    }
    return @($Pattern)
}

function Decode-PassthroughRead {
    param([string]$Line)
    return [System.Text.RegularExpressions.Regex]::Replace(
        $Line,
        '%([0-9A-Fa-f]{2})',
        { param($Match) [string][char][Convert]::ToInt32($Match.Groups[1].Value, 16) }
    )
}

function Compress-PlainTextFile {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [string]$Compression
    )
    $Program = if ($Compression -eq 'gzip') { 'gzip' } else { 'bzip2' }
    $Psi = [System.Diagnostics.ProcessStartInfo]::new()
    $Psi.FileName = $Program
    $Psi.UseShellExecute = $false
    $Psi.RedirectStandardOutput = $true
    $Psi.RedirectStandardError = $true
    $Psi.Arguments = Join-WindowsProcessArguments @('-c', $InputPath)

    $Proc = [System.Diagnostics.Process]::new()
    $Proc.StartInfo = $Psi
    [void]$Proc.Start()
    $OutputStream = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    try {
        $Proc.StandardOutput.BaseStream.CopyTo($OutputStream)
    } finally {
        $OutputStream.Dispose()
    }
    $ErrText = $Proc.StandardError.ReadToEnd()
    $Proc.WaitForExit()
    if ($Proc.ExitCode -ne 0) {
        Fail("$Program failed while writing '$OutputPath': $ErrText`n")
    }
}

function New-PassthroughReadWriter {
    param(
        [string]$OutputPath,
        [string]$Compression,
        [System.Collections.Generic.List[object]]$CompressionTasks,
        [System.Collections.Generic.List[string]]$LocalTemps
    )
    if ([string]::IsNullOrEmpty($Compression)) {
        return (New-LfWriter $OutputPath)
    }

    $TempPath = New-TempFileName 'passthrough.txt'
    $LocalTemps.Add($TempPath)
    $CompressionTasks.Add([pscustomobject]@{
        InputPath = $TempPath
        OutputPath = $OutputPath
        Compression = $Compression
    })
    return (New-LfWriter $TempPath)
}

function Invoke-AlignWithPassthrough {
    param(
        [string]$ExePath,
        [string[]]$NativeArgs,
        [string]$CaptureOutput,
        [hashtable]$ReadFiles,
        [hashtable]$ReadCompression,
        [bool]$FilterUnaligned
    )

    $SamWriter = $null
    $WritersToClose = New-Object System.Collections.Generic.List[object]
    $CompressionTasks = New-Object System.Collections.Generic.List[object]
    $LocalTemps = New-Object System.Collections.Generic.List[string]
    $ReadWriters = @{}
    $ExitCode = 1
    try {
        if ($CaptureOutput -and $CaptureOutput -ne '-') {
            $SamWriter = New-LfWriter $CaptureOutput
            $WritersToClose.Add($SamWriter)
        }

        foreach ($Key in @('al', 'un', 'al-conc', 'al-conc-disc', 'un-conc')) {
            if (-not $ReadFiles.ContainsKey($Key)) {
                continue
            }
            $Paths = @(Get-ReadOutputPaths $Key $ReadFiles[$Key])
            $Compression = if ($ReadCompression.ContainsKey($Key)) { $ReadCompression[$Key] } else { '' }
            if ($Paths.Count -eq 2) {
                $ReadWriters[$Key] = @{
                    '1' = New-PassthroughReadWriter $Paths[0] $Compression $CompressionTasks $LocalTemps
                    '2' = New-PassthroughReadWriter $Paths[1] $Compression $CompressionTasks $LocalTemps
                }
                $WritersToClose.Add($ReadWriters[$Key]['1'])
                $WritersToClose.Add($ReadWriters[$Key]['2'])
            } else {
                $ReadWriters[$Key] = New-PassthroughReadWriter $Paths[0] $Compression $CompressionTasks $LocalTemps
                $WritersToClose.Add($ReadWriters[$Key])
            }
        }

        $Psi = [System.Diagnostics.ProcessStartInfo]::new()
        $Psi.FileName = $ExePath
        $Psi.UseShellExecute = $false
        $Psi.RedirectStandardOutput = $true
        $RedirectChildStderr = [bool]$script:LogFileName
        $Psi.RedirectStandardError = $RedirectChildStderr
        $Psi.Arguments = Join-WindowsProcessArguments $NativeArgs

        $Proc = [System.Diagnostics.Process]::new()
        $Proc.StartInfo = $Psi
        [void]$Proc.Start()
        $StderrTask = $null
        if ($RedirectChildStderr) {
            $StderrTask = $Proc.StandardError.ReadToEndAsync()
        }

        while ($true) {
            $Line = $Proc.StandardOutput.ReadLine()
            if ($null -eq $Line) {
                break
            }

            $Filtered = $false
            if (-not $Line.StartsWith('@')) {
                $Fields = $Line -split "`t", 4
                $Flag = 0
                if ($Fields.Count -gt 1) {
                    [void][int]::TryParse($Fields[1], [ref]$Flag)
                }
                $Unaligned = (($Flag -band 4) -ne 0)
                $Secondary = (($Flag -band 256) -ne 0)
                if ($FilterUnaligned -and $Unaligned) {
                    $Filtered = $true
                }

                $ReadLine = $Proc.StandardOutput.ReadLine()
                if ($null -ne $ReadLine -and $ReadWriters.Count -gt 0) {
                    $Decoded = Decode-PassthroughRead $ReadLine
                    $Mate1 = (($Flag -band 64) -ne 0)
                    $Mate2 = (($Flag -band 128) -ne 0)
                    $Unpaired = (-not $Mate1) -and (-not $Mate2)
                    $Paired = -not $Unpaired

                    if ($Unpaired -and -not $Secondary) {
                        if ($Unaligned -and $ReadWriters.ContainsKey('un')) {
                            $ReadWriters['un'].Write($Decoded)
                        } elseif ((-not $Unaligned) -and $ReadWriters.ContainsKey('al')) {
                            $ReadWriters['al'].Write($Decoded)
                        }
                    }

                    if ($Paired -and -not $Secondary) {
                        $Concordant = (($Flag -band 2) -ne 0)
                        $ConcordantOrDiscordant = (($Flag -band 4) -eq 0) -or (($Flag -band 8) -eq 0)
                        if ($Concordant -and $Mate1 -and $ReadWriters.ContainsKey('al-conc')) {
                            $ReadWriters['al-conc']['1'].Write($Decoded)
                        } elseif ($Concordant -and $Mate2 -and $ReadWriters.ContainsKey('al-conc')) {
                            $ReadWriters['al-conc']['2'].Write($Decoded)
                        } elseif ((-not $Concordant) -and $Mate1 -and $ReadWriters.ContainsKey('un-conc')) {
                            $ReadWriters['un-conc']['1'].Write($Decoded)
                        } elseif ((-not $Concordant) -and $Mate2 -and $ReadWriters.ContainsKey('un-conc')) {
                            $ReadWriters['un-conc']['2'].Write($Decoded)
                        }

                        if ($ConcordantOrDiscordant -and $Mate1 -and $ReadWriters.ContainsKey('al-conc-disc')) {
                            $ReadWriters['al-conc-disc']['1'].Write($Decoded)
                        } elseif ($ConcordantOrDiscordant -and $Mate2 -and $ReadWriters.ContainsKey('al-conc-disc')) {
                            $ReadWriters['al-conc-disc']['2'].Write($Decoded)
                        }
                    }
                }
            }

            if (-not $Filtered) {
                if ($SamWriter) {
                    $SamWriter.Write($Line)
                    $SamWriter.Write("`n")
                } else {
                    [Console]::Out.Write($Line)
                    [Console]::Out.Write("`n")
                }
            }
        }

        $Proc.WaitForExit()
        if ($RedirectChildStderr) {
            $ErrText = $StderrTask.Result
            if ($ErrText.Length -gt 0) {
                Write-StderrText($ErrText)
            }
        }
        $ExitCode = $Proc.ExitCode
    } finally {
        foreach ($Writer in $WritersToClose) {
            $Writer.Dispose()
        }
        foreach ($Task in $CompressionTasks) {
            Compress-PlainTextFile $Task.InputPath $Task.OutputPath $Task.Compression
        }
        if (-not $KeepTemps) {
            foreach ($Path in $LocalTemps) {
                if (Test-Path -LiteralPath $Path) {
                    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    return $ExitCode
}

function Invoke-NativeWithLoggedStderr {
    param(
        [string]$ExePath,
        [string[]]$NativeArgs
    )

    $Psi = [System.Diagnostics.ProcessStartInfo]::new()
    $Psi.FileName = $ExePath
    $Psi.UseShellExecute = $false
    $Psi.RedirectStandardOutput = $false
    $Psi.RedirectStandardError = $true
    $Psi.Arguments = Join-WindowsProcessArguments $NativeArgs

    $Proc = [System.Diagnostics.Process]::new()
    $Proc.StartInfo = $Psi
    [void]$Proc.Start()
    $ErrText = $Proc.StandardError.ReadToEnd()
    $Proc.WaitForExit()
    if ($ErrText.Length -gt 0) {
        Write-StderrText($ErrText)
    }
    return $Proc.ExitCode
}

if (-not (Test-Path -LiteralPath $AlignProgS -PathType Leaf)) {
    Fail("Expected hisat2.ps1 to be in the repository root with hisat2-2.2.2-patch/hisat2-align-s.exe.`n")
}

$Ht2wArgs = New-Object System.Collections.Generic.List[string]
$Ht2Args = New-Object System.Collections.Generic.List[string]
$SawDoubleDash = $false
foreach ($Arg in $ScriptArgs) {
    if ($Arg -eq '--') {
        $SawDoubleDash = $true
        continue
    }
    if ($SawDoubleDash) {
        $Ht2Args.Add($Arg)
    } else {
        $Ht2wArgs.Add($Arg)
    }
}
if (-not $SawDoubleDash) {
    $Ht2Args = New-Object System.Collections.Generic.List[string]
    foreach ($Arg in $Ht2wArgs) {
        $Ht2Args.Add($Arg)
    }
    $Ht2wArgs = New-Object System.Collections.Generic.List[string]
}

$ReadFiles = @{}
$ReadCompression = @{}
for ($i = 0; $i -lt $Ht2Args.Count; $i++) {
    if ($null -eq $Ht2Args[$i] -or $Ht2Args[$i] -eq $RemovedArgMarker) {
        continue
    }
    $Ht2Args[$i] = $Ht2Args[$i].Trim()
}

for ($i = 0; $i -lt $Ht2Args.Count; $i++) {
    if ($null -eq $Ht2Args[$i] -or $Ht2Args[$i] -eq $RemovedArgMarker) {
        continue
    }
    $ArgToken = $Ht2Args[$i]
    $ArgParts = $ArgToken -split '=', 2
    $Arg = $ArgParts[0]
    $InlineValue = if ($ArgParts.Count -gt 1) { $ArgParts[1] } else { $null }

    if ($Arg -eq '-U' -or $Arg -eq '--unpaired' -or ($ArgToken.StartsWith('-U') -and $ArgToken.Length -gt 2) -or $ArgToken.StartsWith('--unpaired=')) {
        $Ht2Args[$i] = $RemovedArgMarker
        if ($ArgToken.StartsWith('-U') -and $ArgToken.Length -gt 2) {
            $Value = $ArgToken.Substring(2)
        } elseif ($ArgToken.StartsWith('--unpaired=')) {
            $Value = $InlineValue
        } else {
            $IndexRef = [ref]$i
            $Value = Get-NextValue ([string[]]$Ht2Args.ToArray()) $IndexRef $Arg
            $i = $IndexRef.Value
            $Ht2Args[$i] = $RemovedArgMarker
        }
        foreach ($ReadName in (Split-CommaValues $Value)) {
            $Ht2wArgs.Add('-U')
            $Ht2wArgs.Add($ReadName)
        }
        continue
    }

    if (($ArgToken -match '^--?([12])(.+)?$') -and ($ArgToken -notmatch '^--?12')) {
        $Mate = $Matches[1]
        $Suffix = $Matches[2]
        $Ht2Args[$i] = $RemovedArgMarker
        if ($Suffix) {
            $Value = $Suffix
        } else {
            $IndexRef = [ref]$i
            $Value = Get-NextValue ([string[]]$Ht2Args.ToArray()) $IndexRef "-$Mate"
            $i = $IndexRef.Value
            $Ht2Args[$i] = $RemovedArgMarker
        }
        foreach ($ReadName in (Split-CommaValues $Value)) {
            $Ht2wArgs.Add("-$Mate")
            $Ht2wArgs.Add($ReadName)
        }
        continue
    }

    switch ($Arg) {
        '--debug' {
            $DebugMode = $true
            $Ht2Args[$i] = $RemovedArgMarker
            continue
        }
        '--no-unal' {
            $NoUnal = $true
            $Ht2Args[$i] = $RemovedArgMarker
            continue
        }
        '--large-index' {
            $LargeIndex = $true
            $Ht2Args[$i] = $RemovedArgMarker
            continue
        }
        '--skip-read-lengths' {
            $SkipReadStat = $true
            $Ht2Args[$i] = $RemovedArgMarker
            continue
        }
        '-c' {
            $SeqInArgs = $true
            continue
        }
        '--temp-directory' {
            $Ht2wArgs.Add($Ht2Args[$i])
            $Ht2Args[$i] = $RemovedArgMarker
            if ($InlineValue) {
                $Ht2wArgs.Add($InlineValue)
            } else {
                $IndexRef = [ref]$i
                $Value = Get-NextValue ([string[]]$Ht2Args.ToArray()) $IndexRef $Arg
                $i = $IndexRef.Value
                $Ht2wArgs.Add($Value)
                $Ht2Args[$i] = $RemovedArgMarker
            }
            continue
        }
    }

    foreach ($ReadArg in @('un-conc', 'al-conc', 'al-conc-disc', 'un', 'al')) {
        if ($Arg -eq "--$ReadArg" -or $Arg -eq "--$ReadArg-gz" -or $Arg -eq "--$ReadArg-bz2") {
            $Ht2Args[$i] = $RemovedArgMarker
            if ($InlineValue) {
                $ReadFiles[$ReadArg] = $InlineValue
            } else {
                $IndexRef = [ref]$i
                $Value = Get-NextValue ([string[]]$Ht2Args.ToArray()) $IndexRef "--$ReadArg"
                $i = $IndexRef.Value
                $ReadFiles[$ReadArg] = $Value
                $Ht2Args[$i] = $RemovedArgMarker
            }
            $ReadCompression[$ReadArg] = ''
            if ($Arg -eq "--$ReadArg-gz") {
                $ReadCompression[$ReadArg] = 'gzip'
            } elseif ($Arg -eq "--$ReadArg-bz2") {
                $ReadCompression[$ReadArg] = 'bzip2'
            }
            break
        }
    }
}

$Passthrough = ($ReadFiles.Count -gt 0 -or $NoUnal)
$CaptureOutput = $null
if ($Passthrough) {
    $Ht2Args.Add('--passthrough')
    $CaptureOutput = '-'
    for ($i = 0; $i -lt $Ht2Args.Count; $i++) {
        if ($null -eq $Ht2Args[$i] -or $Ht2Args[$i] -eq $RemovedArgMarker) {
            continue
        }
        $Arg = $Ht2Args[$i]
        if ($Arg -eq '-S' -or $Arg -eq '--output') {
            $IndexRef = [ref]$i
            $CaptureOutput = Get-NextValue ([string[]]$Ht2Args.ToArray()) $IndexRef $Arg
            $i = $IndexRef.Value
            $Ht2Args[$i - 1] = $RemovedArgMarker
            $Ht2Args[$i] = $RemovedArgMarker
        } elseif ($Arg.StartsWith('--output=')) {
            $CaptureOutput = $Arg.Substring(9)
            $Ht2Args[$i] = $RemovedArgMarker
        }
    }
}

$FilteredHt2Args = New-Object System.Collections.Generic.List[string]
foreach ($Arg in $Ht2Args) {
    if ($null -ne $Arg -and $Arg -ne $RemovedArgMarker) {
        $FilteredHt2Args.Add($Arg)
    }
}
$Ht2Args = $FilteredHt2Args

$Mate1s = New-Object System.Collections.Generic.List[string]
$Mate2s = New-Object System.Collections.Generic.List[string]
$UnpairedReads = New-Object System.Collections.Generic.List[string]
$RefString = $null
$NoNamedPipes = $false
$HelpMode = $false
if ($Ht2wArgs.Count -gt 0) {
    [string[]]$WrapperParseArgs = @($Ht2wArgs.ToArray())
} else {
    [string[]]$WrapperParseArgs = @($Ht2Args.ToArray())
}

for ($i = 0; $i -lt $WrapperParseArgs.Count; $i++) {
    $ArgToken = $WrapperParseArgs[$i]
    $ArgParts = $ArgToken -split '=', 2
    $Arg = $ArgParts[0]
    $InlineValue = if ($ArgParts.Count -gt 1) { $ArgParts[1] } else { $null }

    if (($ArgToken -eq '-1') -or ($ArgToken -eq '--1') -or (($ArgToken -match '^--?1(.+)$') -and ($ArgToken -notmatch '^--?12'))) {
        if ($ArgToken -eq '-1' -or $ArgToken -eq '--1') {
            $IndexRef = [ref]$i
            $Value = Get-NextValue $WrapperParseArgs $IndexRef '-1'
            $i = $IndexRef.Value
        } else {
            $Value = $Matches[1]
        }
        foreach ($ReadName in (Split-CommaValues $Value)) {
            $Mate1s.Add($ReadName)
        }
        continue
    }

    if (($ArgToken -eq '-2') -or ($ArgToken -eq '--2') -or ($ArgToken -match '^--?2(.+)$')) {
        if ($ArgToken -eq '-2' -or $ArgToken -eq '--2') {
            $IndexRef = [ref]$i
            $Value = Get-NextValue $WrapperParseArgs $IndexRef '-2'
            $i = $IndexRef.Value
        } else {
            $Value = $Matches[1]
        }
        foreach ($ReadName in (Split-CommaValues $Value)) {
            $Mate2s.Add($ReadName)
        }
        continue
    }

    if ($ArgToken -eq '-U' -or $ArgToken -eq '--reads' -or $ArgToken -eq '--unpaired' -or $ArgToken.StartsWith('--reads=') -or $ArgToken.StartsWith('--unpaired=') -or ($ArgToken.StartsWith('-U') -and $ArgToken.Length -gt 2)) {
        if ($ArgToken.StartsWith('-U') -and $ArgToken.Length -gt 2) {
            $Value = $ArgToken.Substring(2)
        } elseif ($ArgToken.StartsWith('--reads=') -or $ArgToken.StartsWith('--unpaired=')) {
            $Value = $InlineValue
        } else {
            $IndexRef = [ref]$i
            $Value = Get-NextValue $WrapperParseArgs $IndexRef $Arg
            $i = $IndexRef.Value
        }
        foreach ($ReadName in (Split-CommaValues $Value)) {
            $UnpairedReads.Add($ReadName)
        }
        continue
    }

    if ($Arg -eq '--temp-directory') {
        if ($InlineValue) {
            $TempDir = $InlineValue
        } else {
            $IndexRef = [ref]$i
            $TempDir = Get-NextValue $WrapperParseArgs $IndexRef $Arg
            $i = $IndexRef.Value
        }
        continue
    }

    if ($Arg -eq '--ref-string' -or $Arg -eq '--reference-string') {
        if ($InlineValue) {
            $RefString = $InlineValue
        } else {
            $IndexRef = [ref]$i
            $RefString = Get-NextValue $WrapperParseArgs $IndexRef $Arg
            $i = $IndexRef.Value
        }
        continue
    }

    if ($Arg -eq '--log-file') {
        if ($InlineValue) {
            $LogFileName = $InlineValue
        } else {
            $IndexRef = [ref]$i
            $LogFileName = Get-NextValue $WrapperParseArgs $IndexRef $Arg
            $i = $IndexRef.Value
        }
        continue
    }

    switch ($Arg) {
        '--bam' { continue }
        '--no-named-pipes' { $NoNamedPipes = $true; continue }
        '--keep' { $KeepTemps = $true; continue }
        '--verbose' { $VerboseMode = $true; continue }
        '--help' { $HelpMode = $true; continue }
        '-h' { $HelpMode = $true; continue }
    }
}

for ($i = 0; $i -lt $ScriptArgs.Count; $i++) {
    $ArgToken = $ScriptArgs[$i]
    if ($ArgToken -eq '--') {
        continue
    }
    $ArgParts = $ArgToken -split '=', 2
    $Arg = $ArgParts[0]
    $InlineValue = if ($ArgParts.Count -gt 1) { $ArgParts[1] } else { $null }

    if ($Arg -eq '--log-file') {
        if ($InlineValue) {
            $LogFileName = $InlineValue
        } else {
            $IndexRef = [ref]$i
            $LogFileName = Get-NextValue $ScriptArgs $IndexRef $Arg
            $i = $IndexRef.Value
        }
        Remove-OptionFromList $Ht2Args @('--log-file') $true
        continue
    }

    if ($Arg -eq '--ref-string' -or $Arg -eq '--reference-string') {
        if ($InlineValue) {
            $RefString = $InlineValue
        } else {
            $IndexRef = [ref]$i
            $RefString = Get-NextValue $ScriptArgs $IndexRef $Arg
            $i = $IndexRef.Value
        }
        Remove-OptionFromList $Ht2Args @('--ref-string', '--reference-string') $true
        continue
    }

    if ($Arg -eq '--temp-directory') {
        if ($InlineValue) {
            $TempDir = $InlineValue
        } else {
            $IndexRef = [ref]$i
            $TempDir = Get-NextValue $ScriptArgs $IndexRef $Arg
            $i = $IndexRef.Value
        }
        Remove-OptionFromList $Ht2Args @('--temp-directory') $true
        continue
    }

    switch ($Arg) {
        '--bam' {
            Remove-OptionFromList $Ht2Args @('--bam') $false
            continue
        }
        '--keep' {
            $KeepTemps = $true
            Remove-OptionFromList $Ht2Args @('--keep') $false
            continue
        }
        '--no-named-pipes' {
            $NoNamedPipes = $true
            Remove-OptionFromList $Ht2Args @('--no-named-pipes') $false
            continue
        }
        '--verbose' {
            $VerboseMode = $true
            continue
        }
    }
}

if ($ScriptArgs -contains '--version' -or $ScriptArgs -contains '--help' -or $ScriptArgs -contains '-h') {
    $NativeArgs = @('--wrapper', 'basic-0') + @(Get-DefinedListValues $Ht2Args)
    & $AlignProg @NativeArgs
    exit $LASTEXITCODE
}

Info("Before arg handling:`n")
Info("  Wrapper args:`n[ $($Ht2wArgs -join ' ') ]`n")
Info("  Binary args:`n[ $($Ht2Args -join ' ') ]`n")

$ReadFilesForStats = if ($UnpairedReads.Count -gt 0) { @($UnpairedReads.ToArray()) } else { @($Mate1s.ToArray()) }
if (($ReadFilesForStats.Count -gt 0) -and (-not $SeqInArgs) -and (-not $SkipReadStat) -and ($ReadFilesForStats[0] -ne '-')) {
    Info("Check read length: $($ReadFilesForStats[0])`n")
    $ReadLengthString = Get-ReadLengthString $ReadFilesForStats[0] 10000
    if ($ReadLengthString -and $ReadLengthString -ne '0') {
        Info("Read Length String: $ReadLengthString`n")
        $Ht2Args.Add('--read-lengths')
        $Ht2Args.Add($ReadLengthString)
    }
}

if (-not $SeqInArgs) {
    Check-ReadFilesExist ([string[]]$UnpairedReads.ToArray()) ([string[]]$Mate1s.ToArray()) ([string[]]$Mate2s.ToArray())
}

$ToDelete = New-Object System.Collections.Generic.List[string]
try {
    if (Test-ReadWrappingNeeded ([string[]]$UnpairedReads.ToArray()) ([string[]]$Mate1s.ToArray()) ([string[]]$Mate2s.ToArray())) {
        Info("Using temporary files for compressed input on Windows.`n")
        if ($Mate2s.Count -gt 0) {
            if ($Mate2s.Count -ne $Mate1s.Count) {
                Fail("Different number of files specified with --reads/-1 as with -2`n")
            }
            $Mate1Temp = Expand-ReadFilesToTemp ([string[]]$Mate1s.ToArray()) 'mate1'
            $Mate2Temp = Expand-ReadFilesToTemp ([string[]]$Mate2s.ToArray()) 'mate2'
            $ToDelete.Add($Mate1Temp)
            $ToDelete.Add($Mate2Temp)
            $Ht2Args.Add('-1')
            $Ht2Args.Add($Mate1Temp)
            $Ht2Args.Add('-2')
            $Ht2Args.Add($Mate2Temp)
        }
        if ($UnpairedReads.Count -gt 0) {
            $UnpairedTemp = Expand-ReadFilesToTemp ([string[]]$UnpairedReads.ToArray()) 'unp'
            $ToDelete.Add($UnpairedTemp)
            $Ht2Args.Add('-U')
            $Ht2Args.Add($UnpairedTemp)
        }
    } else {
        if ($Mate2s.Count -gt 0) {
            $Ht2Args.Add('-1')
            $Ht2Args.Add(([string]::Join(',', [string[]]$Mate1s.ToArray())))
            $Ht2Args.Add('-2')
            $Ht2Args.Add(([string]::Join(',', [string[]]$Mate2s.ToArray())))
        }
        if ($UnpairedReads.Count -gt 0) {
            $Ht2Args.Add('-U')
            $Ht2Args.Add(([string]::Join(',', [string[]]$UnpairedReads.ToArray())))
        }
    }

    if ($RefString) {
        if (-not (Test-Path -LiteralPath $BuildScript -PathType Leaf)) {
            Fail("Could not find build wrapper: $BuildScript`n")
        }
        $RefFile = New-TempFileName 'ref_str.fa'
        [System.IO.File]::WriteAllText($RefFile, ">1`n$RefString`n", [System.Text.Encoding]::ASCII)
        $ToDelete.Add($RefFile)
        & $BuildScript $RefFile $RefFile
        if ($LASTEXITCODE -ne 0) {
            Fail("hisat2-build returned non-0 exit level.`n")
        }
        $Ht2Args.Add('--index')
        $Ht2Args.Add($RefFile)
        foreach ($Part in 1..8) {
            $ToDelete.Add("$RefFile.$Part.$IndexExt")
        }
    }

    Info("After arg handling:`n")
    Info("  Binary args:`n[ $($Ht2Args -join ' ') ]`n")

    $IndexName = Extract-IndexNameFrom ([string[]]$Ht2Args.ToArray()) ([bool]$RefString)
    if ($null -ne $IndexName) {
        if ($LargeIndex) {
            Info("Using a large index enforced by user.`n")
            $AlignProg = $AlignProgL
            $IndexExt = $IndexExtL
            if (-not (Test-IndexPart $IndexName $IndexExtL)) {
                Fail("Cannot find the large index $IndexName.1.$IndexExtL`n")
            }
            Info("Using large index ($IndexName.1.$IndexExtL).`n")
        } elseif ((Test-IndexPart $IndexName $IndexExtL) -and -not (Test-IndexPart $IndexName $IndexExtS)) {
            Info("Cannot find a small index but a large one seems to be present.`n")
            Info("Switching to using the large index ($IndexName.1.$IndexExtL).`n")
            $AlignProg = $AlignProgL
            $IndexExt = $IndexExtL
        } else {
            Info("Using the small index ($IndexName.1.$IndexExtS).`n")
        }
    }

    if ($DebugMode) {
        $AlignProg = Add-DebugSuffix $AlignProg
    }
    if (-not (Test-Path -LiteralPath $AlignProg -PathType Leaf)) {
        Fail("Could not find executable: $AlignProg`n")
    }

    $NativeArgs = @('--wrapper', 'basic-0') + @(Get-DefinedListValues $Ht2Args)
    Info("$AlignProg $($NativeArgs -join ' ')`n")
    if ($Passthrough) {
        $Ret = Invoke-AlignWithPassthrough $AlignProg ([string[]]$NativeArgs) $CaptureOutput $ReadFiles $ReadCompression $NoUnal
    } else {
        if ($LogFileName) {
            $Ret = Invoke-NativeWithLoggedStderr $AlignProg ([string[]]$NativeArgs)
        } else {
            & $AlignProg @NativeArgs
            $Ret = $LASTEXITCODE
        }
    }

    if ($Ret -ne 0) {
        ErrorText("hisat2-align exited with value $Ret`n")
    }
    exit $Ret
} finally {
    if (-not $KeepTemps) {
        foreach ($Path in $ToDelete) {
            if (Test-Path -LiteralPath $Path) {
                Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
