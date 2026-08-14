#!/usr/bin/env bash
# ====================================================================
# Siya Infotech & Solar Energy - Production Android Release Script
# ====================================================================

set -e

echo "[1/6] Cleaning Flutter build..."
flutter clean

echo "[2/6] Fetching dependencies..."
flutter pub get

echo "[3/6] Running static code analysis..."
flutter analyze

echo "[4/6] Building Production Release APK..."
flutter build apk --release

echo "[5/6] Creating release directories..."
mkdir -p releases/latest
mkdir -p release-page/releases/latest

echo "[6/6] Copying APK to releases and free download page..."
cp -f build/app/outputs/flutter-apk/app-release.apk releases/Siya-Infotech-Solar-v1.0.0.apk
cp -f build/app/outputs/flutter-apk/app-release.apk releases/latest/Siya-Infotech-Solar-latest.apk
cp -f build/app/outputs/flutter-apk/app-release.apk release-page/releases/Siya-Infotech-Solar-v1.0.0.apk
cp -f build/app/outputs/flutter-apk/app-release.apk release-page/releases/latest/Siya-Infotech-Solar-latest.apk

echo "===================================================================="
echo "SUCCESS! Release APK generated and copied to:"
echo " - releases/Siya-Infotech-Solar-v1.0.0.apk"
echo " - releases/latest/Siya-Infotech-Solar-latest.apk"
echo " - release-page/releases/Siya-Infotech-Solar-v1.0.0.apk"
echo "===================================================================="
