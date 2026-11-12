@echo off
setlocal
cd /d "%~dp0.."
set VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set VS=%%i
if not defined VS (echo Visual Studio C++ tools not found & exit /b 1)
call "%VS%\VC\Auxiliary\Build\vcvars64.bat" >NUL || exit /b 1
if not defined ANDROID_HOME set ANDROID_HOME=%ANDROID_SDK_ROOT%
if not defined CMAKE_HOME set CMAKE_HOME=%ANDROID_HOME%\cmake\4.1.2\bin
"%CMAKE_HOME%\cmake.exe" -S native -B build\native-host -G Ninja -DCMAKE_MAKE_PROGRAM="%CMAKE_HOME%\ninja.exe" -DCMAKE_BUILD_TYPE=Release || exit /b 1
"%CMAKE_HOME%\cmake.exe" --build build\native-host || exit /b 1
