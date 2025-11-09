@echo off
REM Simple batch file to backup C:\Users to Samba share using robocopy
REM This is a simpler alternative to the PowerShell script

REM Configuration - Edit these values
set SOURCE=C:\Users
set DEST=\\server\btrfs\backups\users
set LOGFILE=%~dp0backup_log.txt
set INTERVAL=5

REM Exclude common temp/cache directories
set EXCLUDE_DIRS=AppData\Local\Temp AppData\Local\Microsoft\Windows\INetCache AppData\Local\Microsoft\Windows\WebCache AppData\Roaming\Microsoft\Windows\Recent $Recycle.Bin

echo [%date% %time%] Starting backup from %SOURCE% to %DEST% >> %LOGFILE%

REM Robocopy command with common options:
REM /E - Copy subdirectories including empty ones
REM /COPYALL - Copy all file information
REM /R:3 - Retry 3 times
REM /W:5 - Wait 5 seconds between retries
REM /MT:8 - Multi-threaded (8 threads)
REM /NP - No progress
REM /NDL - No directory list
REM /NFL - No file list

:backup
echo [%date% %time%] Running robocopy backup...

robocopy "%SOURCE%" "%DEST%" /E /COPYALL /R:3 /W:5 /MT:8 /NP /NDL /NFL /LOG+:%LOGFILE% /XD %EXCLUDE_DIRS%

REM Robocopy exit codes: 0-7 = success, 8+ = error
if %ERRORLEVEL% LEQ 7 (
    echo [%date% %time%] Backup completed successfully (Exit code: %ERRORLEVEL%) >> %LOGFILE%
) else (
    echo [%date% %time%] Backup failed with exit code: %ERRORLEVEL% >> %LOGFILE%
)

echo [%date% %time%] Waiting %INTERVAL% minutes until next backup...
timeout /t %INTERVAL% /nobreak >nul
goto backup

