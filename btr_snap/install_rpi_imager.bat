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
    echo Found Raspberry Pi Imager at: %IMAGER_PATH_64%
    set "IMAGER_PATH=%IMAGER_PATH_64%"
    goto :launch
)
if exist "%IMAGER_PATH_32%" (
    echo Found Raspberry Pi Imager at: %IMAGER_PATH_32%
    set "IMAGER_PATH=%IMAGER_PATH_32%"
    goto :launch
)

:: Check in user's AppData (portable installation)
for /f "tokens=*" %%i in ('where /r "%LOCALAPPDATA%" rpi-imager.exe 2^>nul') do (
    echo Found Raspberry Pi Imager at: %%i
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

:: Step 3: Find the bootfs VFAT partition and copy .sh files
echo.
echo ========================================
echo Step 2: Copying .sh files to bootfs partition
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
                echo Found bootfs partition at: %%d:\
                goto :found_bootfs
            ) else if exist "%%d:\boot\" (
                set "BOOTFS_DRIVE=%%d:"
                set "BOOTFS_FOUND=1"
                echo Found bootfs partition at: %%d:\
                goto :found_bootfs
            ) else if exist "%%d:\config.txt" (
                set "BOOTFS_DRIVE=%%d:"
                set "BOOTFS_FOUND=1"
                echo Found bootfs partition at: %%d:\
                goto :found_bootfs
            )
        )
    )
)

:found_bootfs
if "%BOOTFS_FOUND%"=="0" (
    echo.
    echo ERROR: Could not find bootfs (VFAT) partition.
    echo Please make sure:
    echo   1. The SD card is inserted
    echo   2. The SD card has been written with Raspberry Pi OS
    echo   3. The partition is mounted and accessible
    echo.
    echo Available drives:
    for %%d in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
        if exist "%%d:\" (
            echo   %%d:\
        )
    )
    pause
    exit /b 1
)

echo.
echo Bootfs partition found: %BOOTFS_DRIVE%\
echo.

:: Create /boot directory if it doesn't exist
if not exist "%BOOTFS_DRIVE%\boot\" (
    echo Creating /boot directory...
    mkdir "%BOOTFS_DRIVE%\boot\"
)

:: Copy all .sh files to /boot
echo Copying .sh files to %BOOTFS_DRIVE%\boot\...
set "SCRIPT_DIR=%~dp0"
set "FILES_COPIED=0"

for %%f in ("%SCRIPT_DIR%*.sh") do (
    echo   Copying %%~nxf...
    copy /Y "%%f" "%BOOTFS_DRIVE%\boot\" >nul 2>&1
    if !errorlevel! equ 0 (
        set /a FILES_COPIED+=1
    ) else (
        echo   WARNING: Failed to copy %%~nxf
    )
)

if %FILES_COPIED% equ 0 (
    echo.
    echo ERROR: No .sh files were copied.
    echo Please check that .sh files exist in: %SCRIPT_DIR%
    pause
    exit /b 1
)

echo.
echo Successfully copied %FILES_COPIED% file(s) to %BOOTFS_DRIVE%\boot\
echo.

:: Step 4: Append to firmware/firstboot.sh
echo ========================================
echo Step 3: Updating firmware/firstboot.sh
echo ========================================
echo.

set "FIRSTBOOT_FILE=%BOOTFS_DRIVE%\firmware\firstboot.sh"

if not exist "%FIRSTBOOT_FILE%" (
    echo Creating firmware directory and firstboot.sh...
    if not exist "%BOOTFS_DRIVE%\firmware\" (
        mkdir "%BOOTFS_DRIVE%\firmware\"
    )
    (
        echo #!/bin/bash
        echo # First boot script
    ) > "%FIRSTBOOT_FILE%"
)

echo Appending 'bash /boot/setup.sh' to firstboot.sh...
echo bash /boot/setup.sh >> "%FIRSTBOOT_FILE%"

if errorlevel 1 (
    echo.
    echo ERROR: Failed to update firstboot.sh
    pause
    exit /b 1
)

echo.
echo Successfully updated firstboot.sh
echo.

:: Verify the update
echo Verifying firstboot.sh contents:
echo ----------------------------------------
type "%FIRSTBOOT_FILE%"
echo ----------------------------------------
echo.

echo ========================================
echo Setup completed successfully!
echo ========================================
echo.
echo Summary:
echo   - FAT32 partition created (if needed)
echo   - .sh files copied to %BOOTFS_DRIVE%\boot\
echo   - firstboot.sh updated to run setup.sh
echo.
echo The SD card is ready to use!
echo.
pause
endlocal

