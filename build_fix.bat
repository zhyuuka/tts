@echo off

:: Fix Flutter build issues
echo Fixing Flutter build issues...

:: Clean Kotlin daemon temporary files
echo Cleaning Kotlin daemon temporary files...
if exist "%USERPROFILE%\AppData\Local\kotlin\daemon" (
    rd /s /q "%USERPROFILE%\AppData\Local\kotlin\daemon"
    echo Kotlin daemon files cleaned
)

:: Clean Flutter cache
echo Cleaning Flutter cache...
flutter clean

:: Get dependencies
echo Getting dependencies...
flutter pub get

:: Build APK
echo Building APK...
flutter build apk --release

if %errorlevel% neq 0 (
    echo Error: APK build failed
    pause
    exit /b 1
)

echo APK build successful!
echo APK file path: build\app\outputs\flutter-apk\app-release.apk

pause
