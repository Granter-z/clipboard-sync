@echo off
set "PROGRAMFILES(X86)=C:\Program Files (x86)"
set "PATH=C:\Windows\system32;C:\Windows;C:\Windows\System32\Wbem;C:\Windows\System32\WindowsPowerShell\v1.0;C:\Program Files\Git\cmd;D:\flutter\bin;D:\Visual Studio\VC\Tools\MSVC\14.50.35717\bin\Hostx64\x64"
echo Starting flutter build at %DATE% %TIME% > build_log.txt
cd /d "C:\Users\Granter\Desktop\???\clip_sync"
call D:\flutter\bin\flutter.bat build windows --debug >> build_log.txt 2>&1
echo Exit code: %ERRORLEVEL% >> build_log.txt
echo Done at %DATE% %TIME% >> build_log.txt
