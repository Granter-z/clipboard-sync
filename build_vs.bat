@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo Setting up Visual Studio build environment...

:: Critical: set this before anything else
set "PROGRAMFILES(X86)=C:\Program Files (x86)"

:: Find and run vcvarsall to set up MSVC env
set "VS_DIR=D:\Visual Studio"
set "VCVARS=%VS_DIR%\VC\Auxiliary\Build\vcvarsall.bat"

if not exist "%VCVARS%" (
    echo ERROR: vcvarsall.bat not found at %VCVARS%
    pause
    exit /b 1
)

echo Found Visual Studio at %VS_DIR%
echo Running vcvarsall.bat for x64...
call "%VCVARS%" x64

:: Add cmake to PATH (bundled with VS)
set "PATH=%PATH%;%VS_DIR%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"

:: Add Git to PATH
set "PATH=%PATH%;C:\Program Files\Git\cmd"

:: Ensure Flutter is in PATH
set "PATH=%PATH%;D:\flutter\bin"

echo.
echo === Environment Details ===
where cmake
where git
where flutter
echo PROGRAMFILES(X86) = %PROGRAMFILES(X86)%
echo ==========================
echo.

:: Go to project
cd /d "C:\Users\Granter\Desktop\Clipboard Sync\clip_sync"
echo Project dir: %CD%
echo.

:: Clean build
echo [1/3] Cleaning...
call flutter clean >nul 2>&1

echo [2/3] Getting dependencies...
call flutter pub get

echo [3/3] Building Windows (debug)...
echo.
call flutter build windows --debug

set BUILD_RESULT=%ERRORLEVEL%
echo.
echo =========================================
if %BUILD_RESULT% EQU 0 (
    echo  Build SUCCESSFUL!
    echo  Output: build\windows\x64\runner\Debug\clip_sync.exe
    dir "build\windows\x64\runner\Debug\clip_sync.exe"
) else (
    echo  Build FAILED with error code: %BUILD_RESULT%
)
echo =========================================
echo.
pause
endlocal
