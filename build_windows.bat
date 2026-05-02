@echo off
set PROGRAMFILES(X86)=C:\Program Files (x86)
set PATH=%PATH%;D:\Visual Studio\VC\Tools\MSVC\14.50.35717\bin\Hostx64\x64
echo Environment set. Building Windows...
cd /d C:\Users\Granter\Desktop\剪切板\clip_sync
D:\flutter\bin\flutter.bat build windows --debug
echo.
echo Build exit code: %ERRORLEVEL%
pause
