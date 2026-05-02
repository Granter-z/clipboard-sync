@echo off
set "PROGRAMFILES(X86)=C:\Program Files (x86)"
set "PATH=%PATH%;D:\Visual Studio\VC\Tools\MSVC\14.50.35717\bin\Hostx64\x64;D:\flutter\bin;C:\Program Files\Git\cmd"
echo Environment set. Building Windows...
cd /d "C:\Users\Granter\Desktop\Clipboard Sync\clip_sync"
call flutter build windows --debug
echo.
echo Build exit code: %ERRORLEVEL%
pause
