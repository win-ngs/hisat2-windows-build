# HISAT2 for Windows: Unofficial Windows Binaries

This repository provides unofficial Windows binaries for the
[HISAT2](https://daehwankimlab.github.io/hisat2/) RNA-seq aligner.

It packages HISAT2 command-line tools built with MSYS2-UCRT64 and PowerShell
ports of the upstream launcher scripts.

These builds are not produced, endorsed, or supported by the upstream HISAT2
project. This is **not an official HISAT2 release**.
Official HISAT2 site: https://daehwankimlab.github.io/hisat2/

## Downloading HISAT2 for Windows

Prebuilt Windows binaries are available from the
[Releases](https://github.com/win-ngs/hisat2-windows-build/releases) page of
this repository.

Download the latest release archive, for example:

```text
hisat2-2.2.2-patch-windows-ucrt64.zip
```

After extracting the archive, you should see:

```text
hisat2-2.2.2-patch-windows-ucrt64/
  hisat2.ps1
  hisat2-build.ps1
  hisat2-inspect.ps1
  hisat2-align-s.exe
  hisat2-align-l.exe
  hisat2-build-s.exe
  hisat2-build-l.exe
  hisat2-inspect-s.exe
  hisat2-inspect-l.exe
  hisat2-repeat.exe
  *.dll
  LICENSE.md
  THIRD_PARTY_NOTICES.txt
  LICENSES/
```

Keep all DLL files in the same folder as the `.exe` files. The DLLs include the
MSYS2-UCRT64 runtime libraries required by the binaries.

## How to Use

This Windows build uses the same command-line options as upstream HISAT2. For
detailed command-line usage, alignment options, index-building options, and
workflow examples, refer to the official
[HISAT2 manual](https://daehwankimlab.github.io/hisat2/manual/).

Use the PowerShell wrappers for normal use:

```powershell
cd C:\Users\you\Downloads\hisat2-2.2.2-patch-windows-ucrt64
.\hisat2.ps1 --version
.\hisat2-build.ps1 --version
.\hisat2-inspect.ps1 --version
```

If your execution policy blocks local scripts, run them through PowerShell with
an explicit bypass for that invocation:

```powershell
powershell -ExecutionPolicy Bypass -File .\hisat2.ps1 --version
```

Build an index and align paired-end FASTQ files:

```powershell
.\hisat2-build.ps1 C:\data\genome.fa C:\data\genome

.\hisat2.ps1 `
  -x C:\data\genome `
  -1 C:\data\reads_1.fq `
  -2 C:\data\reads_2.fq `
  -S C:\data\aligned.sam
```

Inspect an index:

```powershell
.\hisat2-inspect.ps1 -s C:\data\genome
```

The `.exe` files are the companion binaries used by the wrappers. Do not move
only one executable to another folder, because the companion binaries and DLLs
in the ZIP are needed.

## Windows Path and Line Ending Behavior

The PowerShell wrappers pass arguments to the native `.exe` files without
shell-string concatenation, so Windows paths such as `C:\data\reads 1.fq` are
preserved.

Text outputs produced by the patched native binaries and PowerShell wrappers
are written with LF line endings on Windows. This is intentional so outputs are
compatible with Linux-oriented workflows and tests.

For passthrough read-output options such as `--un`, `--al`, and `--al-conc`,
prefer specifying `-S output.sam` explicitly. When passthrough is active and
`-S` is omitted, the wrapper writes SAM text to raw console stdout to preserve
LF line endings.

## Source Tree

The patched upstream source tree is kept under `hisat2-2.2.2-patch/` in this
repository. The binary release ZIP does not include that source tree; it only
contains the Windows executables, wrappers, required DLLs, and documentation.

```text
hisat2-2.2.2-patch/
```

The upstream HISAT2 README and license are kept inside that directory:

```text
hisat2-2.2.2-patch/README.md
hisat2-2.2.2-patch/LICENSE
```

Release ZIP files should be published through GitHub Releases:

https://github.com/win-ngs/hisat2-windows-build/releases

## Building from Source

You do not need to build HISAT2 yourself if you only want to use the released
Windows binary. This section is for maintainers or users who want to recreate
the build.

Install [MSYS2](https://www.msys2.org/) first. Open an MSYS2-UCRT64 shell and
install the build tools:

```sh
pacman -S --needed \
  base-devel \
  mingw-w64-ucrt-x86_64-gcc
```

Build the release binaries from a real MSYS2-UCRT64 shell:

```sh
cd /c/path/to/hisat2-windows-build/hisat2-2.2.2-patch
make clean
make
```

The release executables are created in `hisat2-2.2.2-patch/`. For the release
build used by this repository, strip those generated executables after `make`:

```sh
strip \
  hisat2-align-s.exe \
  hisat2-align-l.exe \
  hisat2-build-s.exe \
  hisat2-build-l.exe \
  hisat2-inspect-s.exe \
  hisat2-inspect-l.exe \
  hisat2-repeat.exe
```

## Validation Performed

This patched build was checked with MSYS2-UCRT64 using:

```text
gcc/g++ 16.1.0
make
```

The following checks were run:

```text
UCRT64 make build
MSYS2-MSYS make build feasibility check
all HISAT2 companion executables --version
PowerShell wrappers --version
--version metadata checked for anonymous build host, ASCII UTC build time, and no -g3 release flag
paired-end alignment smoke test with Windows C:\... paths
paths containing spaces
HISAT2_INDEXES with Windows paths
passthrough read-output options: --un, --al, --un-gz, --al-conc
--log-file in passthrough and non-passthrough paths
LF-only output checks for SAM, summary, logs, and passthrough reads
dist folder execution without MSYS2 in PATH, using colocated DLLs only
```

## MSYS2-UCRT64 Compatibility Patch

This patch section covers newline handling only. The native HISAT2 executables
are changed so Windows/MSYS2-UCRT64 text output stays LF-only instead of being
rewritten to CRLF by the C runtime.

| File | Change | Reason |
|---|---|---|
| `filebuf.h` | Changed `OutFileBuf` file opens to `"wb"` for string, C string, and `setFile()` paths | Prevents CRT CRLF translation for wrapper-selected text output files |
| `hisat2_main.cpp` | Sets `hisat2-align-*` stdout and stderr to `_O_BINARY` on Windows | Keeps SAM stdout and diagnostic stderr LF-only |
| `hisat2_build_main.cpp` | Sets `hisat2-build-*` stdout and stderr to `_O_BINARY` on Windows | Keeps build wrapper/native output LF-only |
| `hisat2_repeat_main.cpp` | Sets `hisat2-repeat` stdout and stderr to `_O_BINARY` on Windows | Keeps repeat tool console output LF-only |
| `hisat2_inspect.cpp` | Sets `hisat2-inspect-*` stdout and stderr to `_O_BINARY` on Windows | Keeps inspect output LF-only |
| `hisat2.cpp` | Opens alignment summary and novel splice-site output files with `ios::binary` | Keeps summary and splice-site text files LF-only |
| `repeat_builder.cpp` | Opens `.rep.*.seed`, `.rep.snp`, `.rep.info`, `.rep.haplotype`, and `.rep.fa` files with `ios_base::binary` | Keeps repeat annotation text files LF-only |

The modified source locations include comments explaining the Windows/UCRT64
change where native code was changed.

## PowerShell Wrapper Scripts

The upstream launcher scripts were ported to PowerShell for this Windows
release:

| Script | Source behavior | Purpose |
|---|---|---|
| `hisat2.ps1` | Reimplements the upstream Perl `hisat2` wrapper | Preserves Windows paths, spaces, wrapper options, passthrough read files, and LF output |
| `hisat2-build.ps1` | Reimplements the upstream Python `hisat2-build` dispatcher | Selects small/large/debug build binaries without Python |
| `hisat2-inspect.ps1` | Reimplements the upstream Python `hisat2-inspect` dispatcher | Selects small/large/debug inspect binaries without Python |

## Release Build Metadata Changes

The release build also changes `hisat2-2.2.2-patch/Makefile` so `--version`
output is suitable for public Windows binaries:

| Area | Change | Reason |
|---|---|---|
| Build metadata | Replaced `hostname` with `Windows-UCRT64 release build` and changed `date` to UTC ISO format for `BUILD_TIME` | Avoids embedding a local machine name and avoids locale-dependent mojibake in `--version` |
| Release flags | Removed `-g3` from `RELEASE_FLAGS` | Keeps release binaries and the reported `Options:` line free of debug-info flags |
| Release assertions | Added `$(NOASSERT_FLAGS)` to `hisat2-inspect-s/l` release targets | Makes inspect release targets consistent with align/build/repeat release targets that already use `-DNDEBUG` |

## License

HISAT2 is distributed under the GNU General Public License version 3. See
[LICENSE.md](LICENSE.md). In the repository source tree, the original upstream
license is also kept at `hisat2-2.2.2-patch/LICENSE`.

Runtime DLLs included in release ZIP files come from MSYS2 packages and retain
their respective upstream licenses. See
[THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt) and the [LICENSES](LICENSES)
directory for package and license details.
