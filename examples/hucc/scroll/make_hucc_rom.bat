rem ***************************************************************************
@echo off
set HUCC_HOME=C:\PCEngine\huc

set PATH=%HUCC_HOME%\bin;%PATH%
set PCE_INCLUDE=%HUCC_HOME%\include\hucc
set FILE_NAME=scroll.c
set OUTPUT_FILE=%FILE_NAME:.c=.pce%

@cls
@REM Clean
@del %OUTPUT_FILE%

hucc -O2 %FILE_NAME%
pause
