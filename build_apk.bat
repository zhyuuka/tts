@echo off

rem 编译生成release APK
echo 正在编译生成release APK...

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
