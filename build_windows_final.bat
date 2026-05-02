@echo off
echo ========================================
echo  Clipboard Sync - Windows Build Script
echo ========================================
echo.
echo Setting up environment variables...

:: Set PROGRAMFILES(X86) if missing
set "PROGRAMFILES(X86)=C:\Program Files (x86)"

:: Add VS tools to PATH
set "PATH=%PATH%;D:\Visual Studio\VC\Tools\MSVC\14.50.35717\bin\Hostx64\x64"

:: Add Flutter and Git
set "PATH=%PATH%;D:\flutter\bin;C:\Program Files\Git\cmd"

cd /d "C:\Users\Granter\Desktop\Clipboard Sync\clip_sync"

echo.
echo Starting Flutter Windows build...
echo ========================================
echo.

call flutter build windows --debug

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo  Build SUCCESSFUL!
    echo  Output: build\windows\x64\runner\Debug\
    echo ========================================
) else (
    echo.
    echo ========================================
    echo  Build FAILED with error code: %ERRORLEVEL%
    echo ========================================
)

pause
