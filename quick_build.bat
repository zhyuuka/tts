@echo off
echo Quick APK Build
flutter build apk --release
if %errorlevel% equ 0 (
    echo ========================================
    echo BUILD SUCCESSFUL!
    echo APK: build\app\outputs\flutter-apk\app-release.apk
    echo ========================================
) else (
    echo BUILD FAILED
)
pause
