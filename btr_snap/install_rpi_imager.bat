@echo off
setlocal enabledelayedexpansion

:: Batch file to download, install, and run Raspberry Pi Imager
:: Requires administrator privileges

:: Check for administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo This script requires administrator privileges.
    echo Please right-click and select "Run as administrator"
    pause
    exit /b 1
)

echo ========================================
echo Raspberry Pi Imager Installer
echo ========================================
echo.

:: Define variables
set "IMAGER_URL=https://downloads.raspberrypi.com/imager/imager_latest.exe"
set "IMAGER_EXE=%TEMP%\rpi-imager-installer.exe"
set "IMAGER_PATH_64=C:\Program Files\Raspberry Pi Imager\rpi-imager.exe"
set "IMAGER_PATH_32=C:\Program Files (x86)\Raspberry Pi Imager\rpi-imager.exe"

:: Check if Raspberry Pi Imager is already installed
echo Checking for existing installation...
if exist "%IMAGER_PATH_64%" (
    echo Found Raspberry Pi Imager at: "%IMAGER_PATH_64%"
    set "IMAGER_PATH=%IMAGER_PATH_64%"
    goto :launch
)
if exist "%IMAGER_PATH_32%" (
    echo Found Raspberry Pi Imager at: "%IMAGER_PATH_32%"
    set "IMAGER_PATH=%IMAGER_PATH_32%"
    goto :launch
)

:: Check in user's AppData (portable installation)
for /f "tokens=*" %%i in ('where /r "%LOCALAPPDATA%" rpi-imager.exe 2^>nul') do (
    echo Found Raspberry Pi Imager at: "%%i"
    set "IMAGER_PATH=%%i"
    goto :launch
)

:: Not found, need to download and install
echo Raspberry Pi Imager not found. Downloading...
echo.

:: Download Raspberry Pi Imager
echo Downloading from: %IMAGER_URL%
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -Uri '%IMAGER_URL%' -OutFile '%IMAGER_EXE%' -UseBasicParsing; exit 0 } catch { Write-Host 'Download failed: ' $_.Exception.Message; exit 1 }"

if not exist "%IMAGER_EXE%" (
    echo.
    echo ERROR: Failed to download Raspberry Pi Imager.
    echo Please check your internet connection and try again.
    pause
    exit /b 1
)

echo Download complete.
echo.

:: Install Raspberry Pi Imager silently
echo Installing Raspberry Pi Imager...
echo This may take a moment...
start /wait "" "%IMAGER_EXE%" /S

if errorlevel 1 (
    echo.
    echo ERROR: Installation failed.
    echo Please try installing manually from: https://www.raspberrypi.com/software/
    del "%IMAGER_EXE%" 2>nul
    pause
    exit /b 1
)

echo Installation complete.
echo.

:: Clean up installer
del "%IMAGER_EXE%" 2>nul

:: Wait a moment for installation to complete
timeout /t 2 /nobreak >nul

:: Check for installed location
if exist "%IMAGER_PATH_64%" (
    set "IMAGER_PATH=%IMAGER_PATH_64%"
) else if exist "%IMAGER_PATH_32%" (
    set "IMAGER_PATH=%IMAGER_PATH_32%"
) else (
    echo ERROR: Installation completed but could not find Raspberry Pi Imager executable.
    echo Please launch it manually from the Start menu.
    pause
    exit /b 1
)

:launch
echo Launching Raspberry Pi Imager...
echo.
start "" "%IMAGER_PATH%"

if errorlevel 1 (
    echo ERROR: Failed to launch Raspberry Pi Imager.
    echo Please try launching it manually from the Start menu.
    pause
    exit /b 1
)

echo.
echo Raspberry Pi Imager has been launched successfully!
echo.
echo Please use Raspberry Pi Imager to write the OS image to your SD card.
echo After you're done, close Raspberry Pi Imager and this script will continue.
echo.
echo Waiting for Raspberry Pi Imager to close...
:wait_imager
timeout /t 5 /nobreak >nul
tasklist /FI "IMAGENAME eq rpi-imager.exe" 2>nul | find /I /N "rpi-imager.exe">nul
if "%ERRORLEVEL%"=="0" goto wait_imager

echo.
echo Raspberry Pi Imager has been closed.
echo.

:: Step 2: Run the PowerShell script to create FAT32 partition
echo ========================================
echo Step 1: Creating FAT32 partition
echo ========================================
echo.

set "PS_SCRIPT=%~dp0setup_btrfs_partition.ps1"
if not exist "%PS_SCRIPT%" (
    echo ERROR: Could not find setup_btrfs_partition.ps1
    echo Expected location: %PS_SCRIPT%
    pause
    exit /b 1
)

echo Running PowerShell script to create partition...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"

if errorlevel 1 (
    echo.
    echo WARNING: PowerShell script returned an error.
    echo You may need to manually create the partition or check for errors.
    echo.
)

:: Step 3: Find the bootfs VFAT partition and copy .sh and .py files
echo.
echo ========================================
echo Step 2: Copying .sh and .py files to bootfs partition
echo ========================================
echo.

:: Wait a moment for partitions to be recognized
timeout /t 3 /nobreak >nul

:: Find VFAT/FAT32 partition (bootfs)
set "BOOTFS_DRIVE="
set "BOOTFS_FOUND=0"

echo Searching for bootfs (VFAT/FAT32) partition...
echo.

:: Check all available drive letters
for %%d in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%d:\" (
        :: Check if it's a VFAT/FAT32 partition by checking filesystem
        powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $vol = Get-Volume -DriveLetter '%%d' -ErrorAction SilentlyContinue; if ($vol -and ($vol.FileSystemType -eq 'FAT32' -or $vol.FileSystemType -eq 'FAT')) { Write-Host 'Found VFAT partition: %%d:\'; exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
        if !errorlevel! equ 0 (
            :: Check if it looks like a bootfs partition (has boot files or firmware folder)
            if exist "%%d:\firmware\" (
                set "BOOTFS_DRIVE=%%d:"
                set "BOOTFS_FOUND=1"
                echo Found bootfs partition at: %%d:
                goto :found_bootfs
            ) else if exist "%%d:\boot\" (
                set "BOOTFS_DRIVE=%%d:"
                set "BOOTFS_FOUND=1"
                echo Found bootfs partition at: %%d:
                goto :found_bootfs
            ) else if exist "%%d:\config.txt" (
                set "BOOTFS_DRIVE=%%d:"
                set "BOOTFS_FOUND=1"
                echo Found bootfs partition at: %%d:
                goto :found_bootfs
            )
        )
    )
)

:found_bootfs
if "%BOOTFS_FOUND%"=="0" (
    echo.
    echo ERROR: Could not find bootfs VFAT partition.
    echo Please make sure:
    echo   1. The SD card is inserted
    echo   2. The SD card has been written with Raspberry Pi OS
    echo   3. The partition is mounted and accessible
    echo.
    echo Available drives:
    for %%d in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
        if exist "%%d:\" (
            echo   %%d:
        )
    )
    pause
    exit /b 1
)

:: Verify BOOTFS_DRIVE is set
if not defined BOOTFS_DRIVE (
    echo ERROR: BOOTFS_DRIVE variable is not set.
    pause
    exit /b 1
)

echo.
echo Bootfs partition found: !BOOTFS_DRIVE!
echo.

:: Create btrnas directory if it doesn't exist
set "BTRNAS_DIR=!BOOTFS_DRIVE!\btrnas"
echo Checking for btrnas directory at: !BTRNAS_DIR!
if not exist "!BTRNAS_DIR!" (
    echo Creating btrnas directory...
    :: Try creating the directory
    mkdir "!BTRNAS_DIR!" 2>nul
    if errorlevel 1 (
        echo.
        echo ERROR: Failed to create btrnas directory
        echo Attempting alternative method...
        :: Try using md command
        md "!BTRNAS_DIR!" 2>nul
        if errorlevel 1 (
            echo ERROR: All directory creation methods failed.
            echo Please check permissions and try again.
            echo Bootfs drive: !BOOTFS_DRIVE!
            pause
            exit /b 1
        )
    )
    echo btrnas directory created successfully.
) else (
    echo btrnas directory already exists.
)

:: Verify directory exists
if not exist "!BTRNAS_DIR!" (
    echo.
    echo ERROR: btrnas directory does not exist after creation attempt.
    echo.
    echo Debug: Listing contents of !BOOTFS_DRIVE!\:
    dir /b "!BOOTFS_DRIVE!\"
    echo.
    echo Please verify the bootfs partition is writable.
    pause
    exit /b 1
)

:: Debug: List contents to verify
echo Verifying btrnas directory exists...
dir /b "!BTRNAS_DIR!" >nul 2>&1
if errorlevel 1 (
    echo WARNING: Cannot list contents of btrnas directory, but directory check passed.
) else (
    echo btrnas directory verified successfully.
)
echo.

:: Copy all .sh and .py files to btrnas
echo Copying .sh and .py files to !BTRNAS_DIR!\...
set "SCRIPT_DIR=%~dp0"
set "FILES_COPIED=0"

for %%f in ("%SCRIPT_DIR%*.sh") do (
    echo   Copying %%~nxf...
    copy /Y "%%f" "!BTRNAS_DIR!\" >nul 2>&1
    if !errorlevel! equ 0 (
        set /a FILES_COPIED+=1
    ) else (
        echo   WARNING: Failed to copy %%~nxf
    )
)

for %%f in ("%SCRIPT_DIR%*.py") do (
    echo   Copying %%~nxf...
    copy /Y "%%f" "!BTRNAS_DIR!\" >nul 2>&1
    if !errorlevel! equ 0 (
        set /a FILES_COPIED+=1
    ) else (
        echo   WARNING: Failed to copy %%~nxf
    )
)

if !FILES_COPIED! equ 0 (
    echo.
    echo ERROR: No .sh or .py files were copied.
    echo Please check that .sh or .py files exist in: %SCRIPT_DIR%
    pause
    exit /b 1
)

echo.
echo Successfully copied !FILES_COPIED! file(s) to !BTRNAS_DIR!
echo.

:: Step 4: Append to firmware/firstboot.sh, firmware/firstrun.sh, firstboot.sh, or firstrun.sh
echo ========================================
echo Step 3: Updating firstboot/firstrun script
echo ========================================
echo.

set "FIRMWARE_FIRSTBOOT=!BOOTFS_DRIVE!\firmware\firstboot.sh"
set "FIRMWARE_FIRSTRUN=!BOOTFS_DRIVE!\firmware\firstrun.sh"
set "ROOT_FIRSTBOOT=!BOOTFS_DRIVE!\firstboot.sh"
set "ROOT_FIRSTRUN=!BOOTFS_DRIVE!\firstrun.sh"
set "FIRSTBOOT_FILE="

:: Check for firstboot.sh or firstrun.sh in firmware/ first, then root
if exist "!FIRMWARE_FIRSTBOOT!" (
    set "FIRSTBOOT_FILE=!FIRMWARE_FIRSTBOOT!"
    echo Found firmware/firstboot.sh
) else if exist "!FIRMWARE_FIRSTRUN!" (
    set "FIRSTBOOT_FILE=!FIRMWARE_FIRSTRUN!"
    echo Found firmware/firstrun.sh
) else if exist "!ROOT_FIRSTBOOT!" (
    set "FIRSTBOOT_FILE=!ROOT_FIRSTBOOT!"
    echo Found firstboot.sh in root
) else if exist "!ROOT_FIRSTRUN!" (
    set "FIRSTBOOT_FILE=!ROOT_FIRSTRUN!"
    echo Found firstrun.sh in root
) else (
    echo.
    echo ERROR: Could not find firstboot.sh or firstrun.sh
    echo Searched for:
    echo   - !FIRMWARE_FIRSTBOOT!
    echo   - !FIRMWARE_FIRSTRUN!
    echo   - !ROOT_FIRSTBOOT!
    echo   - !ROOT_FIRSTRUN!
    echo.
    echo Something has gone wrong. The firstboot/firstrun script should exist on the bootfs partition.
    echo Please verify the SD card has been written with Raspberry Pi OS correctly.
    pause
    exit /b 1
)

:: File exists, need to insert before exit 0 or append (only if line doesn't already exist)
echo Updating !FIRSTBOOT_FILE!...
echo Checking if command already exists...

:: Use PowerShell to check if line exists, and if not, insert before exit 0 or append
powershell -NoProfile -ExecutionPolicy Bypass -Command "$file = '!FIRSTBOOT_FILE!'; $command = 'bash /boot/btrnas/setup.sh'; $lines = Get-Content $file; $alreadyExists = $false; $newLines = @(); $inserted = $false; $foundExit = $false; foreach ($line in $lines) { if ($line -match [regex]::Escape($command)) { $alreadyExists = $true; }; if ($line -match '^\s*exit\s+0\s*$') { $foundExit = $true; if (-not $inserted -and -not $alreadyExists) { $newLines += $command; $inserted = $true; } }; $newLines += $line; }; if ($alreadyExists) { Write-Host 'Command already exists in script, skipping.' -ForegroundColor Green; exit 0 }; if (-not $inserted) { $newLines += $command; if (-not $foundExit) { $newLines += 'exit 0'; } }; Set-Content -Path $file -Value $newLines; if (-not $foundExit) { Write-Host 'WARNING: exit 0 not found in script' -ForegroundColor Yellow; exit 1 } else { Write-Host 'Successfully updated script' -ForegroundColor Green; exit 0 }"

if errorlevel 1 (
    echo.
    echo WARNING: exit 0 was not found in the script
    echo The command has been added, but please verify the file manually.
    echo.
) else (
    echo Script check/update completed
)

echo.

:: Verify the update
echo Verifying script contents:
echo ----------------------------------------
type "!FIRSTBOOT_FILE!"
echo ----------------------------------------
echo.

echo ========================================
echo Setup completed successfully!
echo ========================================
echo.
echo Summary:
echo   - FAT32 partition created (if needed)
echo   - .sh and .py files copied to !BTRNAS_DIR!
echo   - firstboot/firstrun script updated to run setup.sh
echo.
echo The SD card is ready to use!
echo.

:: Eject the drive
echo Ejecting drive !BOOTFS_DRIVE!...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$drive = '!BOOTFS_DRIVE!'; $driveLetter = $drive.TrimEnd(':'); try { $driveEject = New-Object -comObject Shell.Application; $driveEject.Namespace(17).ParseName($drive).InvokeVerb('Eject'); Start-Sleep -Seconds 2; $stillMounted = Test-Path $drive -ErrorAction SilentlyContinue; if ($stillMounted) { Write-Host 'WARNING: Drive still appears to be mounted after ejection attempt.' -ForegroundColor Yellow; exit 1 } else { Write-Host 'Drive ejected successfully.' -ForegroundColor Green; exit 0 } } catch { Write-Host 'ERROR: Could not eject drive: ' + $_.Exception.Message -ForegroundColor Red; exit 1 }"

if errorlevel 1 (
    echo WARNING: Could not eject drive automatically, or drive is still mounted.
    echo You may need to eject it manually from Windows Explorer.
) else (
    echo Drive ejected successfully.
)

echo.
endlocal

