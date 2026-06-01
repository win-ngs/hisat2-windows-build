# Runtime DLL License Files

This directory records license information for DLLs bundled in
`hisat2-2.2.2-patch-windows-ucrt64.zip`.

The DLLs were copied from an MSYS2-UCRT64 installation. Package ownership was
checked with `pacman -Qo`, and package metadata was checked with `pacman -Qi`.

| DLL | MSYS2 package | Version | License |
|---|---|---|---|
| `libgcc_s_seh-1.dll` | `mingw-w64-ucrt-x86_64-gcc-libs` | `16.1.0-2` | `spdx:GPL-3.0-or-later WITH GCC-exception-3.1 AND LGPL-2.1-or-later` |
| `libstdc++-6.dll` | `mingw-w64-ucrt-x86_64-gcc-libs` | `16.1.0-2` | `spdx:GPL-3.0-or-later WITH GCC-exception-3.1 AND LGPL-2.1-or-later` |
| `libwinpthread-1.dll` | `mingw-w64-ucrt-x86_64-libwinpthread` | `14.0.0.r37.g2bfe61fba-1` | `spdx:MIT AND BSD-3-Clause-Clear` |

Some DLLs also have separate per-DLL detail files in this directory. The table
above is the authoritative list for the current ZIP contents.
