@echo off
rem Runs inside Warframe's wine session. %1 = this folder (windows path), %2 = original Warframe launcher, rest = its args.
set DATA=%~1
shift
set EXE=%~1
shift
set ARGS=
:loop
if "%~1"=="" goto run
set ARGS=%ARGS% %1
shift
goto loop
:run
rem AlecaFrame's extension id; if it isn't installed yet, run its installer from the data folder instead.
set EXT=C:\users\steamuser\AppData\Local\Overwolf\Extensions\afmcagbpgggkpdkokjhjkllpegnadmkignlonpjm
if exist "%EXT%" (
  start "" "C:\Program Files (x86)\Overwolf\OverwolfLauncher.exe" -launchapp afmcagbpgggkpdkokjhjkllpegnadmkignlonpjm -ow-disable-gpu
) else (
  if exist "%DATA%\AlecaFrame - Installer.exe" start "" "%DATA%\AlecaFrame - Installer.exe"
)
for %%i in ("%EXE%") do pushd "%%~dpi"
start "" /wait "%EXE%" %ARGS%
