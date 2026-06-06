@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0hisat2-build.ps1" %*
exit /b %ERRORLEVEL%
