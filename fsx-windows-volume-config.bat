@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem FSx for Windows backup and maintenance windows (view/update)
rem Usage:
rem   fsx-windows-volume-config.bat -id <fsx-id> [options]
rem   fsx-windows-volume-config.bat -file <path> [options]

set "REGION=%AWS_REGION%"
set "PROFILE=%AWS_PROFILE%"
set "ID="
set "FILE="
set "BACKUP_INPUT="
set "MAINT_INPUT="
set "BACKUP_PLUS="
set "BACKUP_MINUS="
set "MAINT_PLUS="
set "MAINT_MINUS="

if "%~1"=="" goto :usage

:parse_args
if "%~1"=="" goto :after_parse
if /i "%~1"=="-id" (
  if "%~2"=="" goto :usage_err
  set "ID=%~2"
  shift
  shift
  goto :parse_args
)
if /i "%~1"=="-file" (
  if "%~2"=="" goto :usage_err
  set "FILE=%~2"
  shift
  shift
  goto :parse_args
)
if /i "%~1"=="-backup" (
  if "%~2"=="" goto :usage_err
  set "BACKUP_INPUT=%~2"
  shift
  shift
  goto :parse_args
)
if /i "%~1"=="-backup-plushours" (
  if "%~2"=="" goto :usage_err
  set "BACKUP_PLUS=%~2"
  shift
  shift
  goto :parse_args
)
if /i "%~1"=="-backup-minushours" (
  if "%~2"=="" goto :usage_err
  set "BACKUP_MINUS=%~2"
  shift
  shift
  goto :parse_args
)
if /i "%~1"=="-maintenance" (
  if "%~2"=="" goto :usage_err
  set "MAINT_INPUT=%~2"
  shift
  shift
  goto :parse_args
)
if /i "%~1"=="-maintenance-plushours" (
  if "%~2"=="" goto :usage_err
  set "MAINT_PLUS=%~2"
  shift
  shift
  goto :parse_args
)
if /i "%~1"=="-maintenance-minushours" (
  if "%~2"=="" goto :usage_err
  set "MAINT_MINUS=%~2"
  shift
  shift
  goto :parse_args
)
if /i "%~1"=="-region" (
  if "%~2"=="" goto :usage_err
  set "REGION=%~2"
  shift
  shift
  goto :parse_args
)
if /i "%~1"=="-profile" (
  if "%~2"=="" goto :usage_err
  set "PROFILE=%~2"
  shift
  shift
  goto :parse_args
)
if /i "%~1"=="-help" goto :usage
if /i "%~1"=="/?" goto :usage

echo ERROR: Unknown option "%~1".
goto :usage_err

:after_parse
if defined ID if defined FILE (
  echo ERROR: Use either -id or -file, not both.
  goto :usage_err
)
if not defined ID if not defined FILE (
  echo ERROR: Either -id or -file is required.
  goto :usage_err
)
if defined BACKUP_PLUS if defined BACKUP_MINUS (
  echo ERROR: Use either -backup-plushours or -backup-minushours, not both.
  goto :usage_err
)
if defined MAINT_PLUS if defined MAINT_MINUS (
  echo ERROR: Use either -maintenance-plushours or -maintenance-minushours, not both.
  goto :usage_err
)

call :validate_inputs
if errorlevel 1 goto :usage_err

where aws >nul 2>nul
if errorlevel 1 (
  echo AWS CLI not found. Install awscli and ensure "aws" is on PATH.
  exit /b 1
)

set "COMMON_OPTS="
if defined REGION set "COMMON_OPTS=%COMMON_OPTS% --region %REGION%"
if defined PROFILE set "COMMON_OPTS=%COMMON_OPTS% --profile %PROFILE%"

if defined FILE (
  if not exist "%FILE%" (
    echo ERROR: Input file not found: "%FILE%".
    exit /b 1
  )
  set "HAS_IDS="
  set "ANY_FAILURE="
  for /f "usebackq delims=" %%I in ("%FILE%") do (
    set "LINE="
    set "RAW=%%I"
    for /f "tokens=* delims= " %%J in ("!RAW!") do set "LINE=%%J"
    if defined LINE (
      set "FIRST=!LINE:~0,1!"
      if /i not "!FIRST!"=="#" if /i not "!FIRST!"==";" (
        set "HAS_IDS=1"
        call :process_id "!LINE!"
        if errorlevel 1 set "ANY_FAILURE=1"
      )
    )
  )
  if not defined HAS_IDS (
    echo ERROR: Input file is empty: "%FILE%".
    exit /b 1
  )
  if defined ANY_FAILURE exit /b 1
  exit /b 0
)

call :process_id "%ID%"
exit /b %errorlevel%

:process_id
set "FSX_ID=%~1"
if "%FSX_ID%"=="" exit /b 0

call :fetch_windows_times "%FSX_ID%"
if errorlevel 1 exit /b 1

echo === %FSX_ID% ===
echo Backup window: %CURRENT_BACKUP%
echo Maintenance window: %CURRENT_MAINT%

set "NEW_BACKUP="
set "NEW_MAINT="
if defined BACKUP_PLUS (
  call :compute_backup_new
  if errorlevel 1 exit /b 1
) else if defined BACKUP_MINUS (
  call :compute_backup_new
  if errorlevel 1 exit /b 1
) else if defined BACKUP_INPUT (
  call :compute_backup_new
  if errorlevel 1 exit /b 1
)
if defined MAINT_PLUS (
  call :compute_maint_new
  if errorlevel 1 exit /b 1
) else if defined MAINT_MINUS (
  call :compute_maint_new
  if errorlevel 1 exit /b 1
) else if defined MAINT_INPUT (
  call :compute_maint_new
  if errorlevel 1 exit /b 1
)

set "WINDOWS_CONFIG="
if defined NEW_BACKUP set "WINDOWS_CONFIG=DailyAutomaticBackupStartTime=%NEW_BACKUP%"
if defined NEW_MAINT (
  if defined WINDOWS_CONFIG (
    set "WINDOWS_CONFIG=!WINDOWS_CONFIG!,WeeklyMaintenanceStartTime=%NEW_MAINT%"
  ) else (
    set "WINDOWS_CONFIG=WeeklyMaintenanceStartTime=%NEW_MAINT%"
  )
)

if defined WINDOWS_CONFIG (
  echo Applying update...
  call :update_windows "%FSX_ID%" "%WINDOWS_CONFIG%"
  if errorlevel 1 exit /b 1
)

echo.
exit /b 0

:fetch_windows_times
set "FSX_ID=%~1"
set "CURRENT_BACKUP="
set "CURRENT_MAINT="
set "TMP_FILE=%TEMP%\fsx-windows-%RANDOM%%RANDOM%.txt"

aws fsx describe-file-systems --file-system-ids "%FSX_ID%" %COMMON_OPTS% --query "FileSystems[0].WindowsConfiguration.[DailyAutomaticBackupStartTime,WeeklyMaintenanceStartTime]" --output text > "%TMP_FILE%" 2> "%TMP_FILE%.err"
if errorlevel 1 (
  echo ERROR: Failed to describe file system "%FSX_ID%".
  type "%TMP_FILE%.err"
  del "%TMP_FILE%" "%TMP_FILE%.err" >nul 2>nul
  exit /b 1
)

for /f "usebackq tokens=1,2 delims=	" %%A in ("%TMP_FILE%") do (
  set "CURRENT_BACKUP=%%A"
  set "CURRENT_MAINT=%%B"
)

del "%TMP_FILE%" "%TMP_FILE%.err" >nul 2>nul

if not defined CURRENT_BACKUP (
  echo ERROR: Backup window not found for "%FSX_ID%".
  exit /b 1
)
if not defined CURRENT_MAINT (
  echo ERROR: Maintenance window not found for "%FSX_ID%".
  exit /b 1
)
if /i "%CURRENT_BACKUP%"=="None" (
  echo ERROR: Backup window not available for "%FSX_ID%".
  exit /b 1
)
if /i "%CURRENT_MAINT%"=="None" (
  echo ERROR: Maintenance window not available for "%FSX_ID%".
  exit /b 1
)

exit /b 0

:compute_backup_new
set "NEW_BACKUP="
if defined BACKUP_PLUS (
  set "OFFSET_INPUT=%BACKUP_PLUS%"
  set "OFFSET_SIGN=+"
) else if defined BACKUP_MINUS (
  set "OFFSET_INPUT=%BACKUP_MINUS%"
  set "OFFSET_SIGN=-"
) else (
  set "INPUT=%BACKUP_INPUT%"
  call :parse_hh_mm "!INPUT!"
  if errorlevel 1 (
    echo ERROR: Invalid backup value "%BACKUP_INPUT%".
    exit /b 1
  )
  call :format_two "!PARSE_H!" OUT_H
  call :format_two "!PARSE_M!" OUT_M
  set "NEW_BACKUP=!OUT_H!:!OUT_M!"
  exit /b 0
)

call :validate_digits "%OFFSET_INPUT%"
if errorlevel 1 (
  echo ERROR: Invalid backup hours value "%OFFSET_INPUT%".
  exit /b 1
)
call :parse_backup_current
if errorlevel 1 (
  echo ERROR: Unable to parse current backup time "%CURRENT_BACKUP%".
  exit /b 1
)
call :strip_leading_zeros "%OFFSET_INPUT%" OFFSET_STR
if "%OFFSET_STR%"=="" set "OFFSET_STR=0"
set /a "OFFSET_HOURS=%OFFSET_STR%"
if "%OFFSET_SIGN%"=="-" set /a "OFFSET_HOURS=-OFFSET_HOURS"
set /a "TOTAL=(PARSE_H * 60 + PARSE_M) + (OFFSET_HOURS * 60)"
set /a "TOTAL=((TOTAL %% 1440) + 1440) %% 1440"
set /a "NEW_H=TOTAL / 60"
set /a "NEW_M=TOTAL %% 60"
call :format_two "%NEW_H%" OUT_H
call :format_two "%NEW_M%" OUT_M
set "NEW_BACKUP=%OUT_H%:%OUT_M%"
exit /b 0

:compute_maint_new
set "NEW_MAINT="
if defined MAINT_PLUS (
  set "OFFSET_INPUT=%MAINT_PLUS%"
  set "OFFSET_SIGN=+"
) else if defined MAINT_MINUS (
  set "OFFSET_INPUT=%MAINT_MINUS%"
  set "OFFSET_SIGN=-"
) else (
  set "INPUT=%MAINT_INPUT%"
  call :parse_d_hh_mm "!INPUT!"
  if errorlevel 1 (
    echo ERROR: Invalid maintenance value "%MAINT_INPUT%".
    exit /b 1
  )
  call :format_two "!PARSE_H!" OUT_H
  call :format_two "!PARSE_M!" OUT_M
  set "NEW_MAINT=!PARSE_D!:!OUT_H!:!OUT_M!"
  exit /b 0
)

call :validate_digits "%OFFSET_INPUT%"
if errorlevel 1 (
  echo ERROR: Invalid maintenance hours value "%OFFSET_INPUT%".
  exit /b 1
)
call :parse_d_hh_mm "%CURRENT_MAINT%"
if errorlevel 1 (
  echo ERROR: Unable to parse current maintenance time "%CURRENT_MAINT%".
  exit /b 1
)
call :strip_leading_zeros "%OFFSET_INPUT%" OFFSET_STR
if "%OFFSET_STR%"=="" set "OFFSET_STR=0"
set /a "OFFSET_HOURS=%OFFSET_STR%"
if "%OFFSET_SIGN%"=="-" set /a "OFFSET_HOURS=-OFFSET_HOURS"
set /a "TOTAL=((PARSE_D - 1) * 1440) + (PARSE_H * 60) + PARSE_M + (OFFSET_HOURS * 60)"
set /a "TOTAL=((TOTAL %% 10080) + 10080) %% 10080"
set /a "NEW_D=(TOTAL / 1440) + 1"
set /a "NEW_H=(TOTAL %% 1440) / 60"
set /a "NEW_M=TOTAL %% 60"
call :format_two "%NEW_H%" OUT_H
call :format_two "%NEW_M%" OUT_M
set "NEW_MAINT=%NEW_D%:%OUT_H%:%OUT_M%"
exit /b 0

:update_windows
set "FSX_ID=%~1"
set "WINDOWS_CONFIG=%~2"
set "TMP_FILE=%TEMP%\fsx-update-%RANDOM%%RANDOM%.txt"

aws fsx update-file-system --file-system-id "%FSX_ID%" --windows-configuration %WINDOWS_CONFIG% %COMMON_OPTS% --query "FileSystem.WindowsConfiguration.[DailyAutomaticBackupStartTime,WeeklyMaintenanceStartTime]" --output text > "%TMP_FILE%" 2> "%TMP_FILE%.err"
if errorlevel 1 (
  echo ERROR: Failed to update file system "%FSX_ID%".
  type "%TMP_FILE%.err"
  del "%TMP_FILE%" "%TMP_FILE%.err" >nul 2>nul
  exit /b 1
)

set "UPDATED_BACKUP="
set "UPDATED_MAINT="
for /f "usebackq tokens=1,2 delims=	" %%A in ("%TMP_FILE%") do (
  set "UPDATED_BACKUP=%%A"
  set "UPDATED_MAINT=%%B"
)

del "%TMP_FILE%" "%TMP_FILE%.err" >nul 2>nul

if defined UPDATED_BACKUP echo Updated backup window: %UPDATED_BACKUP%
if defined UPDATED_MAINT echo Updated maintenance window: %UPDATED_MAINT%
exit /b 0

:validate_inputs
if defined BACKUP_PLUS (
  call :validate_digits "%BACKUP_PLUS%"
  if errorlevel 1 (
    echo ERROR: Invalid -backup-plushours value "%BACKUP_PLUS%".
    exit /b 1
  )
  call :validate_hours_limit "%BACKUP_PLUS%"
  if errorlevel 1 (
    echo ERROR: -backup-plushours must be between 0 and 12.
    exit /b 1
  )
) else if defined BACKUP_MINUS (
  call :validate_digits "%BACKUP_MINUS%"
  if errorlevel 1 (
    echo ERROR: Invalid -backup-minushours value "%BACKUP_MINUS%".
    exit /b 1
  )
  call :validate_hours_limit "%BACKUP_MINUS%"
  if errorlevel 1 (
    echo ERROR: -backup-minushours must be between 0 and 12.
    exit /b 1
  )
) else if defined BACKUP_INPUT (
  call :parse_hh_mm "%BACKUP_INPUT%"
  if errorlevel 1 (
    echo ERROR: Invalid -backup value "%BACKUP_INPUT%".
    exit /b 1
  )
)
if defined MAINT_PLUS (
  call :validate_digits "%MAINT_PLUS%"
  if errorlevel 1 (
    echo ERROR: Invalid -maintenance-plushours value "%MAINT_PLUS%".
    exit /b 1
  )
  call :validate_hours_limit "%MAINT_PLUS%"
  if errorlevel 1 (
    echo ERROR: -maintenance-plushours must be between 0 and 12.
    exit /b 1
  )
) else if defined MAINT_MINUS (
  call :validate_digits "%MAINT_MINUS%"
  if errorlevel 1 (
    echo ERROR: Invalid -maintenance-minushours value "%MAINT_MINUS%".
    exit /b 1
  )
  call :validate_hours_limit "%MAINT_MINUS%"
  if errorlevel 1 (
    echo ERROR: -maintenance-minushours must be between 0 and 12.
    exit /b 1
  )
 ) else if defined MAINT_INPUT (
  call :parse_d_hh_mm "%MAINT_INPUT%"
  if errorlevel 1 (
    echo ERROR: Invalid -maintenance value "%MAINT_INPUT%".
    exit /b 1
  )
)
exit /b 0

:validate_digits
set "CHECK=%~1"
set "NONNUM="
if "%CHECK%"=="" exit /b 1
for /f "delims=0123456789" %%A in ("%CHECK%") do set "NONNUM=%%A"
if defined NONNUM exit /b 1
exit /b 0

:validate_hours_limit
set "CHECK=%~1"
call :strip_leading_zeros "%CHECK%" CHECK_STR
if "%CHECK_STR%"=="" set "CHECK_STR=0"
set /a "CHECK_VAL=%CHECK_STR%"
if %CHECK_VAL% gtr 12 exit /b 1
exit /b 0

:strip_leading_zeros
set "NUM_STR=%~1"
if "%NUM_STR%"=="" exit /b 1
:strip_loop
if "%NUM_STR:~0,1%"=="0" if not "%NUM_STR%"=="0" (
  set "NUM_STR=%NUM_STR:~1%"
  goto :strip_loop
)
set "%~2=%NUM_STR%"
exit /b 0

:format_two
set "NUM=%~1"
set "NUM=0%NUM%"
set "NUM=%NUM:~-2%"
set "%~2=%NUM%"
exit /b 0

:parse_hh_mm
set "PARSE_H="
set "PARSE_M="
set "H="
set "M="
set "EXTRA="
for /f "tokens=1,2,3 delims=:" %%A in ("%~1") do (
  set "H=%%A"
  set "M=%%B"
  set "EXTRA=%%C"
)
if not defined H exit /b 1
if not defined M exit /b 1
if defined EXTRA exit /b 1
call :validate_digits "%H%"
if errorlevel 1 exit /b 1
call :validate_digits "%M%"
if errorlevel 1 exit /b 1
call :strip_leading_zeros "%H%" H_STR
if "%H_STR%"=="" set "H_STR=0"
call :strip_leading_zeros "%M%" M_STR
if "%M_STR%"=="" set "M_STR=0"
set /a "H_NUM=%H_STR%"
set /a "M_NUM=%M_STR%"
if %H_NUM% gtr 23 exit /b 1
if %M_NUM% gtr 59 exit /b 1
set "PARSE_H=%H_NUM%"
set "PARSE_M=%M_NUM%"
exit /b 0

:parse_backup_current
set "PARSE_H="
set "PARSE_M="
set "H="
set "M="
set "S="
set "EXTRA="
for /f "tokens=1,2,3,4 delims=:" %%A in ("%CURRENT_BACKUP%") do (
  set "H=%%A"
  set "M=%%B"
  set "S=%%C"
  set "EXTRA=%%D"
)
if not defined H exit /b 1
if not defined M exit /b 1
if defined EXTRA exit /b 1
call :validate_digits "%H%"
if errorlevel 1 exit /b 1
call :validate_digits "%M%"
if errorlevel 1 exit /b 1
if defined S (
  call :validate_digits "%S%"
  if errorlevel 1 exit /b 1
)
call :strip_leading_zeros "%H%" H_STR
if "%H_STR%"=="" set "H_STR=0"
call :strip_leading_zeros "%M%" M_STR
if "%M_STR%"=="" set "M_STR=0"
set /a "H_NUM=%H_STR%"
set /a "M_NUM=%M_STR%"
if %H_NUM% gtr 23 exit /b 1
if %M_NUM% gtr 59 exit /b 1
set "PARSE_H=%H_NUM%"
set "PARSE_M=%M_NUM%"
exit /b 0

:parse_d_hh_mm
set "PARSE_D="
set "PARSE_H="
set "PARSE_M="
set "D="
set "H="
set "M="
set "EXTRA="
for /f "tokens=1,2,3,4 delims=:" %%A in ("%~1") do (
  set "D=%%A"
  set "H=%%B"
  set "M=%%C"
  set "EXTRA=%%D"
)
if not defined D exit /b 1
if not defined H exit /b 1
if not defined M exit /b 1
if defined EXTRA exit /b 1
if not "%D:~1,1%"=="" (
  if not "%D:~2,1%"=="" exit /b 1
  if not "%D:~0,1%"=="0" exit /b 1
)
if "%H:~1,1%"=="" exit /b 1
if not "%H:~2,1%"=="" exit /b 1
if "%M:~1,1%"=="" exit /b 1
if not "%M:~2,1%"=="" exit /b 1
call :validate_digits "%D%"
if errorlevel 1 exit /b 1
call :validate_digits "%H%"
if errorlevel 1 exit /b 1
call :validate_digits "%M%"
if errorlevel 1 exit /b 1
call :strip_leading_zeros "%D%" D_STR
if "%D_STR%"=="" set "D_STR=0"
call :strip_leading_zeros "%H%" H_STR
if "%H_STR%"=="" set "H_STR=0"
call :strip_leading_zeros "%M%" M_STR
if "%M_STR%"=="" set "M_STR=0"
set /a "D_NUM=%D_STR%"
set /a "H_NUM=%H_STR%"
set /a "M_NUM=%M_STR%"
if %D_NUM% lss 1 exit /b 1
if %D_NUM% gtr 7 exit /b 1
if %H_NUM% gtr 23 exit /b 1
if %M_NUM% gtr 60 exit /b 1
set "PARSE_D=%D_NUM%"
set "PARSE_H=%H_NUM%"
set "PARSE_M=%M_NUM%"
exit /b 0

:usage_err
echo.
call :usage
exit /b 1

:usage
echo Usage:
echo   fsx-windows-volume-config.bat -id ^<fsx-id^> [options]
echo   fsx-windows-volume-config.bat -file ^<path^> [options]
echo   (One of -id or -file is required.)
echo   File format: one FSx ID per line; blank lines and lines
echo               starting with # or ; are ignored.
echo.
echo Options:
echo   -backup ^<HH:MM^>                 Daily backup start time (UTC).
echo   -backup-plushours ^<H^>           Offset backup by +H hours (UTC).
echo   -backup-minushours ^<H^>          Offset backup by -H hours (UTC).
echo   -maintenance ^<d:HH:MM^>          Weekly maintenance (UTC), d=1-7.
echo                                     d=1 (Mon) ... d=7 (Sun).
echo                                     HH must be 00-23, MM must be 00-60.
echo   -maintenance-plushours ^<H^>      Offset maintenance by +H hours (UTC).
echo   -maintenance-minushours ^<H^>     Offset maintenance by -H hours (UTC).
echo   Offsets override explicit times when both are provided.
echo   Hour offsets must be between 0 and 12.
echo   -region ^<region^>                AWS region (or AWS_REGION env).
echo   -profile ^<profile^>              AWS profile (or AWS_PROFILE env).
echo   -help or /?                       Show this help.
echo.
echo Examples:
echo   fsx-windows-volume-config.bat -id fs-1234567890abcdef0
echo   fsx-windows-volume-config.bat -file ids.txt -backup-plushours 2
echo   fsx-windows-volume-config.bat -id fs-1234567890abcdef0 -maintenance 7:05:00
echo   fsx-windows-volume-config.bat -id fs-1234567890abcdef0 -maintenance-minushours 1
exit /b 0
