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

rem Rename APK files with version and copy backward-compatible version
set APK_DIR=build\app\outputs\flutter-apk
if /i "%MODE%"=="release" (
    echo.
    echo Renaming APKs with version V%VERSION%...
    
    rem Rename each ABI-specific APK
    if exist "%APK_DIR%\app-arm64-v8a-release.apk" (
        move /y "%APK_DIR%\app-arm64-v8a-release.apk" "%APK_DIR%\AiChat-V%VERSION%-arm64-v8a.apk" >nul
        echo    Created: AiChat-V%VERSION%-arm64-v8a.apk
        
        rem Copy arm64-v8a as backward-compatible version (no ABI suffix)
        copy /y "%APK_DIR%\AiChat-V%VERSION%-arm64-v8a.apk" "%APK_DIR%\AiChat-V%VERSION%.apk" >nul
        echo    Created: AiChat-V%VERSION%.apk (backward compatible)
    )
    
    if exist "%APK_DIR%\app-armeabi-v7a-release.apk" (
        move /y "%APK_DIR%\app-armeabi-v7a-release.apk" "%APK_DIR%\AiChat-V%VERSION%-armeabi-v7a.apk" >nul
        echo    Created: AiChat-V%VERSION%-armeabi-v7a.apk
    )
    
    if exist "%APK_DIR%\app-x86_64-release.apk" (
        move /y "%APK_DIR%\app-x86_64-release.apk" "%APK_DIR%\AiChat-V%VERSION%-x86_64.apk" >nul
        echo    Created: AiChat-V%VERSION%-x86_64.apk
    )
)

echo.
echo ============================================================
echo Build successful! Version: %VERSION%
echo.
echo APK output directory:
echo    %APK_DIR%\
if /i "%MODE%"=="release" (
    echo.
    echo Generated APKs:
    echo    AiChat-V%VERSION%.apk (backward compatible, arm64-v8a)
    echo    AiChat-V%VERSION%-arm64-v8a.apk
    echo    AiChat-V%VERSION%-armeabi-v7a.apk
    echo    AiChat-V%VERSION%-x86_64.apk
)
echo ============================================================
pause
