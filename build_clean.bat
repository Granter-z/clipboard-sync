@echo off
chcp 65001 >nul
title Clipboard Sync Builder

echo =========================================
echo  Clipboard Sync - Windows Build
echo =========================================
echo.

:: Set required env vars (Git Bash doesn't inherit these)
set "PROGRAMFILES(X86)=C:\Program Files (x86)"
set "PATH=%PATH%;C:\Program Files\Git\cmd"

:: Go to project root
cd /d "C:\Users\Granter\Desktop\Clipboard Sync\clip_sync"

echo [1/3] Cleaning previous build...
call flutter clean >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [!] Clean skipped (may already be clean)
)

echo [2/3] Getting dependencies...
call flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] pub get failed!
    pause
    exit /b 1
)

echo [3/3] Building Windows (debug)...
echo.
call flutter build windows --debug
set BUILD_RESULT=%ERRORLEVEL%

echo.
echo =========================================
if %BUILD_RESULT% EQU 0 (
    echo  Build SUCCESSFUL!
    echo  Output: build\windows\x64\runner\Debug\clip_sync.exe
) else (
    echo  Build FAILED with error code: %BUILD_RESULT%
)
echo =========================================
echo.

pause
