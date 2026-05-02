@echo off
set "PROGRAMFILES(X86)=C:\Program Files (x86)"
set "PATH=%PATH%;D:\Visual Studio\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;C:\Program Files\Git\cmd;D:\flutter\bin"
cd /d "C:\Users\Granter\Desktop\Clipboard Sync\clip_sync"
echo == ENV CHECK ==
echo PROGRAMFILES(X86)=%PROGRAMFILES(X86)%
where cmake
where git
where flutter
echo == FLUTTER CLEAN ==
call flutter clean
echo == FLUTTER PUB GET ==
call flutter pub get
echo == FLUTTER BUILD ==
call flutter build windows --debug
echo EXIT_CODE=%ERRORLEVEL%
