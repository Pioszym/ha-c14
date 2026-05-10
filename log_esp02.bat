@echo off
REM Logowanie esp02 do pliku log_esp02_YYYYMMDDHHMM.log w katalogu projektu.
REM Bez podgladu w konsoli, bez kolorow ANSI. Ctrl+C konczy stream.

set NO_COLOR=1
for /f "tokens=2 delims==" %%i in ('wmic os get localdatetime /value') do set dt=%%i
set logfile=log_esp02_%dt:~0,12%.log

echo Logowanie do %logfile%  (Ctrl+C aby zakonczyc)
esphome logs esp02.yaml --device 192.168.88.206 > "%logfile%" 2>&1
