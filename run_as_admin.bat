@echo off

rem 以管理员权限运行修复脚本
:: BatchGotAdmin
:atchGotAdmin
if "%~dp0"=="%~dp0admin" goto :admin
if exist "%temp%\getadmin.vbs" del /f /q "%temp%\getadmin.vbs"
fsutil dirty query %systemdrive% >nul 2>&1
if '%errorlevel%' == '0' goto :admin
if not exist "%temp%\getadmin.vbs" (
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    echo WScript.Quit >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    del /f /q "%temp%\getadmin.vbs"
    exit /b
)

:admin

rem 修复Flutter构建问题
echo 正在修复Flutter构建问题...

rem 清理Kotlin守护进程临时文件
echo 正在清理Kotlin守护进程临时文件...
if exist "%USERPROFILE%\AppData\Local\kotlin\daemon" (
    rd /s /q "%USERPROFILE%\AppData\Local\kotlin\daemon"
    echo Kotlin守护进程临时文件已清理
)

rem 清理Flutter缓存
echo 正在清理Flutter缓存...
call flutter clean

rem 检查依赖
echo 正在检查依赖...
call flutter pub get

rem 构建APK
echo 正在构建APK...
call flutter build apk --release

if %errorlevel% neq 0 (
    echo 错误: APK构建失败
    pause
    exit /b 1
)

echo APK构建成功！
echo APK文件路径: build\app\outputs\flutter-apk\app-release.apk

pause
