@echo off
REM ====================================================================
REM Siya Infotech Staff - Production Android Release Script
REM ====================================================================

echo [1/6] Cleaning Flutter build...
call flutter clean

echo [2/6] Fetching dependencies...
call flutter pub get

echo [3/6] Running static code analysis...
call flutter analyze

echo [4/6] Building Production Release APK...
call flutter build apk --release

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Release APK build failed!
    exit /b %ERRORLEVEL%
)

echo [5/6] Creating release directories...
if not exist "releases" mkdir releases
if not exist "releases\latest" mkdir releases\latest
if not exist "release-page\releases\latest" mkdir release-page\releases\latest

echo [6/6] Copying APK to releases and free download page...
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "releases\Siya-Solar-Staff-v1.0.2.apk"
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "releases\latest\Siya-Solar-Staff-latest.apk"
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "release-page\releases\Siya-Solar-Staff-v1.0.2.apk"
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "release-page\releases\latest\Siya-Solar-Staff-latest.apk"

echo ====================================================================
echo SUCCESS! Release APK generated and copied to:
echo  - releases\Siya-Solar-Staff-v1.0.2.apk
echo  - releases\latest\Siya-Solar-Staff-latest.apk
echo  - release-page\releases\Siya-Solar-Staff-v1.0.2.apk
echo ====================================================================
