# Bundled Binary License Files

This directory records license information for the runtime DLLs and the bundled
bzip2 tool shipped in `hisat2-2.2.2-patch-windows-ucrt64.zip`.

The files were copied from an MSYS2-UCRT64 installation. Package ownership was
checked with `pacman -Qo`, and package metadata was checked with `pacman -Qi`.

| File | MSYS2 package | Version | License |
|---|---|---|---|
| `libgcc_s_seh-1.dll` | `mingw-w64-ucrt-x86_64-gcc-libs` | `16.1.0-2` | `spdx:GPL-3.0-or-later WITH GCC-exception-3.1 AND LGPL-2.1-or-later` |
| `libstdc++-6.dll` | `mingw-w64-ucrt-x86_64-gcc-libs` | `16.1.0-2` | `spdx:GPL-3.0-or-later WITH GCC-exception-3.1 AND LGPL-2.1-or-later` |
| `libwinpthread-1.dll` | `mingw-w64-ucrt-x86_64-libwinpthread` | `14.0.0.r37.g2bfe61fba-1` | `spdx:MIT AND BSD-3-Clause-Clear` |
| `bzip2.exe` | `mingw-w64-ucrt-x86_64-bzip2` | `1.0.8-3` | `custom (bzip2 license, BSD-style)` |
| `libbz2-1.dll` | `mingw-w64-ucrt-x86_64-bzip2` | `1.0.8-3` | `custom (bzip2 license, BSD-style)` |

`bzip2.exe` and `libbz2-1.dll` are only needed for `.bz2` reads; gzip (`.gz`) is
handled in-process by the wrapper via .NET and needs no bundled tool. The full
bzip2 license text is in `bzip2.txt`.

Some files also have separate per-file detail texts in this directory (for
example `bzip2.txt`). The table above is the authoritative list for the current
ZIP contents.
