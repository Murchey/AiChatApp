@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
title AiChat - APK Build Script

rem ============================================================
rem  AiChat Build Script
rem  Usage:
rem    build_apk.bat              -> Build release APK (split per ABI)
rem    build_apk.bat debug        -> Build debug APK
rem  Output: build\app\outputs\flutter-apk\
rem ============================================================

set MODE=release
if /i "%~1"=="debug" set MODE=debug

where flutter >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Flutter not found. Please install Flutter and add to PATH.
    pause
    exit /b 1
)

echo.
echo [1/2] flutter pub get ...
call flutter pub get
if errorlevel 1 (
    echo [ERROR] flutter pub get failed.
    pause
    exit /b 1
)

echo.
echo [2/2] Building APK ...
if /i "%MODE%"=="release" (
    echo     Mode: release (split per ABI)
    call flutter build apk --release --split-per-abi
) else (
    echo     Mode: debug
    call flutter build apk --debug
)
if errorlevel 1 (
    echo [ERROR] flutter build apk failed. Check logs above.
    pause
    exit /b 1
)

rem Read version from pubspec.yaml
set VERSION=0.0.0
for /f "tokens=2 delims=: " %%v in ('findstr /b "version:" pubspec.yaml') do set VERSION=%%v

echo.
echo ============================================================
echo Build successful! Version: %VERSION%
echo.
echo APK output directory:
echo    build\app\outputs\flutter-apk\
if /i "%MODE%"=="release" (
    echo.
    echo Generated APKs:
    echo    app-arm64-v8a-release.apk
    echo    app-armeabi-v7a-release.apk
    echo    app-x86_64-release.apk
)
echo ============================================================
pause
