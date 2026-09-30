@echo off
rem ============================================================================
rem Canonical release AAB build for aori_shogi. Do not hand-run flutter build:
rem a missing flag silently drops obfuscation or debug symbols.
rem Usage: build_aab_release.cmd <build-name> <build-number>
rem    ex: build_aab_release.cmd 1.0.0 1
rem
rem   --split-debug-info : keeps DWARF out of libapp.so (smaller download).
rem                        Symbols are required by Play Console and cannot be
rem                        regenerated, so they are copied to 50_release\.
rem   --obfuscate        : renames Dart symbols.
rem   --target-platform  : arm + arm64 only. yaneuraou_ffi builds both from
rem                        source via CMake; x86_64 is emulator-only.
rem ============================================================================
setlocal
if "%~1"=="" (echo USAGE: build_aab_release.cmd ^<build-name^> ^<build-number^> & exit /b 1)
if "%~2"=="" (echo USAGE: build_aab_release.cmd ^<build-name^> ^<build-number^> & exit /b 1)
set "VER=%~1"
set "NUM=%~2"
cd /d C:\Users\amake\Claude\Projects\aori_shogi
set "ProgramFiles(x86)=C:\Program Files (x86)"
if not exist android\key.properties (echo [sign] KEYPROPS_MISSING & exit /b 1)
set "SYMDIR=build\symbols\%VER%+%NUM%"
echo [build] flutter build appbundle --release %VER%+%NUM% ...
call flutter build appbundle --release --build-name=%VER% --build-number=%NUM% --target-platform android-arm,android-arm64 --obfuscate --split-debug-info=%SYMDIR%
if errorlevel 1 (echo BUILD_FAILED & exit /b 1)
set "AAB=build\app\outputs\bundle\release\app-release.aab"
if not exist "%AAB%" (echo AAB_NOT_FOUND & exit /b 1)
copy /y "%AAB%" "build\aori-shogi-%VER%-b%NUM%.aab" >nul
for %%A in ("build\aori-shogi-%VER%-b%NUM%.aab") do echo [size] %%~zA bytes
rem build\ is disposable. Keep the aab and the symbols outside it.
set "KEEPDIR=C:\Users\amake\Claude\Projects\aori_shogi\50_release"
if not exist "%KEEPDIR%\aab" mkdir "%KEEPDIR%\aab"
if not exist "%KEEPDIR%\symbols\%VER%+%NUM%" mkdir "%KEEPDIR%\symbols\%VER%+%NUM%"
copy /y "build\aori-shogi-%VER%-b%NUM%.aab" "%KEEPDIR%\aab\" >nul
copy /y "%SYMDIR%\*" "%KEEPDIR%\symbols\%VER%+%NUM%\" >nul
echo [keep] %KEEPDIR%\aab\aori-shogi-%VER%-b%NUM%.aab
echo [keep] %KEEPDIR%\symbols\%VER%+%NUM%
echo DONE_AAB
