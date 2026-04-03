@echo off

:: Simple build script for Flutter APK
echo Building Flutter APK...

:: Clean Flutter cache
flutter clean

:: Get dependencies
flutter pub get

:: Build APK
flutter build apk --release

if %errorlevel% neq 0 (
    echo Build failed
    pause
    exit /b 1
)

echo Build successful!
echo APK path: build\app\outputs\flutter-apk\app-release.apk

pause
