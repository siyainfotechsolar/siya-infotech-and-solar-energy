@echo off
REM ====================================================================
REM Siya Infotech Staff - Production Android Release Script
REM Version: 1.0.5+6
REM ====================================================================

echo [1/7] Cleaning Flutter build...
call flutter clean

echo [2/7] Fetching dependencies...
call flutter pub get

echo [3/7] Running static code analysis...
call flutter analyze

echo [4/7] Building Production Release APK...
call flutter build apk --release

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Release APK build failed!
    exit /b %ERRORLEVEL%
)

echo [5/7] Creating release directories...
if not exist "releases" mkdir releases
if not exist "releases\latest" mkdir releases\latest
if not exist "release-page\releases\latest" mkdir release-page\releases\latest

echo [6/7] Copying APK to releases and free download page...
echo [6/7] Copying APK to releases and free download page...
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "releases\Siya-Solar-Staff-v1.0.10.apk"
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "releases\latest\Siya-Solar-Staff-latest.apk"
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "release-page\releases\Siya-Solar-Staff-v1.0.10.apk"
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "release-page\releases\latest\Siya-Solar-Staff-latest.apk"

echo [7/7] Updating Supabase app_releases table...
call dart run scripts/update_release_v1_0_10.dart

echo ====================================================================
echo SUCCESS! Release APK generated and copied to:
echo  - releases\Siya-Solar-Staff-v1.0.10.apk
echo  - releases\latest\Siya-Solar-Staff-latest.apk
echo  - release-page\releases\Siya-Solar-Staff-v1.0.5.apk
echo ====================================================================
