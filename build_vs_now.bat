@echo off
chcp 65001 >nul

:: Critical: set this before anything else
set "PROGRAMFILES(X86)=C:\Program Files (x86)"

:: Find and run vcvarsall to set up MSVC env
set "VS_DIR=D:\Visual Studio"
call "%VS_DIR%\VC\Auxiliary\Build\vcvarsall.bat" x64 >nul 2>&1

:: Add tools to PATH
set "PATH=%PATH%;%VS_DIR%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
set "PATH=%PATH%;C:\Program Files\Git\cmd"
set "PATH=%PATH%;D:\flutter\bin"

:: Print environment
echo CMake: 
where cmake
echo Git: 
where git
echo Flutter: 
where flutter

:: Go to project
cd /d "C:\Users\Granter\Desktop\Clipboard Sync\clip_sync"

echo [1/3] Cleaning...
call flutter clean

echo [2/3] Getting dependencies...
call flutter pub get

echo [3/3] Building...
call flutter build windows --debug
echo EXIT_CODE=%ERRORLEVEL%
