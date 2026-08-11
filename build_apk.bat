@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
title AiChat - APK Build Script

rem ============================================================
rem  AiChat 本地打包脚本
rem  用法：
rem    build_apk.bat              -> 构建 debug APK
rem    build_apk.bat release      -> 构建 release APK
rem  产物：dist\AiChat-V<版本号>.apk（发布 Release 时按此命名上传）
rem ============================================================

set MODE=debug
if /i "%~1"=="release" set MODE=release

where flutter >nul 2>nul
if errorlevel 1 (
    echo [ERROR] 未找到 Flutter，请先安装 Flutter 并加入 PATH 后重试。
    pause
    exit /b 1
)

echo.
echo [1/3] flutter pub get ...
call flutter pub get
if errorlevel 1 (
    echo [ERROR] flutter pub get 失败。
    pause
    exit /b 1
)

echo.
echo [2/3] flutter build apk --%MODE% ...
call flutter build apk --%MODE%
if errorlevel 1 (
    echo [ERROR] flutter build apk --%MODE% 失败，请检查上方日志。
    pause
    exit /b 1
)

rem 从 pubspec.yaml 读取版本号（形如 version: 1.0.0+1）
set VERSION=0.0.0
for /f "tokens=2 delims=: " %%v in ('findstr /b "version:" pubspec.yaml') do set VERSION=%%v

set OUT_DIR=dist
if not exist %OUT_DIR% mkdir %OUT_DIR%

set SRC=build\app\outputs\flutter-apk\app-%MODE%.apk
set DST=%OUT_DIR%\AiChat-V%VERSION%.apk
if not exist "%SRC%" (
    echo [ERROR] 未找到构建产物：%SRC%
    pause
    exit /b 1
)

copy /y "%SRC%" "%DST%" >nul

echo.
echo [3/3] 完成。
echo    APK : %DST%
for %%f in ("%DST%") do echo    大小 : %%~zf bytes
echo.
echo 构建成功！安装包已输出到 %OUT_DIR% 目录。
pause
