@echo off

rem 启动Flutter应用
echo 正在启动Flutter应用...

rem 检查Flutter是否安装
where flutter >nul 2>&1
if %errorlevel% neq 0 (
    echo 错误: Flutter未安装或未添加到环境变量
    pause
    exit /b 1
)

rem 检查依赖
echo 正在检查依赖...
call flutter pub get

if %errorlevel% neq 0 (
    echo 错误: 依赖安装失败
    pause
    exit /b 1
)

rem 启动应用
echo 正在启动应用...
call flutter run

pause
