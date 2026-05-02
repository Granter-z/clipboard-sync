@echo off
set PROGRAMFILES(X86)=C:\Program Files (x86)
cd /d "C:\Users\Granter\Desktop\???\clip_sync"
call D:\flutter\bin\flutter.bat build windows --debug > C:\Users\Granter\Desktop\???\clip_sync\build_result.txt 2>&1
echo EXIT_CODE=%ERRORLEVEL% >> C:\Users\Granter\Desktop\???\clip_sync\build_result.txt
