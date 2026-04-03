@echo off

:: Speed up Flutter build process
echo Speeding up Flutter build process...

:: Create gradle.properties file with optimized settings
echo Creating optimized gradle.properties file...
if not exist "android" mkdir android
if not exist "android\gradle.properties" (
    echo org.gradle.jvmargs=-Xmx4g -XX:MaxPermSize=512m -XX:+HeapDumpOnOutOfMemoryError -Dfile.encoding=UTF-8 > android\gradle.properties
    echo org.gradle.parallel=true >> android\gradle.properties
    echo org.gradle.caching=true >> android\gradle.properties
    echo kotlin.incremental=true >> android\gradle.properties
    echo android.enableR8=true >> android\gradle.properties
    echo AndroidXEnabled=true >> android\gradle.properties
    echo Optimized gradle.properties created
)

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

:: Build APK with optimized settings
echo Building APK with optimized settings...
flutter build apk --release --no-tree-shake-icons

if %errorlevel% neq 0 (
    echo Error: APK build failed
    pause
    exit /b 1
)

echo APK build successful!
echo APK file path: build\app\outputs\flutter-apk\app-release.apk

pause
