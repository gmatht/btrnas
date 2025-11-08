#!/bin/bash
# Linux script to download, install, and run Raspberry Pi Imager
# Then sets up partitions and copies files to bootfs

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root (needed for some operations)
if [[ $EUID -eq 0 ]]; then
    print_warning "Running as root. Some operations may require user privileges."
fi

echo "========================================"
echo "Raspberry Pi Imager Installer (Linux)"
echo "========================================"
echo

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect package manager
detect_package_manager() {
    if command_exists apt; then
        echo "apt"
    elif command_exists dnf; then
        echo "dnf"
    elif command_exists yum; then
        echo "yum"
    elif command_exists pacman; then
        echo "pacman"
    elif command_exists zypper; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# Check if Raspberry Pi Imager is already installed
IMAGER_CMD=""
if command_exists rpi-imager; then
    IMAGER_CMD="rpi-imager"
    print_status "Found Raspberry Pi Imager: rpi-imager"
elif command_exists flatpak && flatpak list | grep -q "org.raspberrypi.rpi-imager"; then
    IMAGER_CMD="flatpak run org.raspberrypi.rpi-imager"
    print_status "Found Raspberry Pi Imager: Flatpak"
elif [ -f "$HOME/Applications/rpi-imager.AppImage" ] || [ -f "/opt/rpi-imager/rpi-imager" ]; then
    if [ -f "$HOME/Applications/rpi-imager.AppImage" ]; then
        IMAGER_CMD="$HOME/Applications/rpi-imager.AppImage"
    else
        IMAGER_CMD="/opt/rpi-imager/rpi-imager"
    fi
    print_status "Found Raspberry Pi Imager: AppImage/Standalone"
fi

# Install if not found
if [ -z "$IMAGER_CMD" ]; then
    print_status "Raspberry Pi Imager not found. Installing..."
    
    PKG_MANAGER=$(detect_package_manager)
    
    case $PKG_MANAGER in
        apt)
            print_status "Installing via apt..."
            if ! command_exists rpi-imager; then
                # Try to install from official repo
                sudo apt update
                if sudo apt install -y rpi-imager 2>/dev/null; then
                    IMAGER_CMD="rpi-imager"
                else
                    print_warning "Could not install via apt. Trying AppImage method..."
                    PKG_MANAGER="appimage"
                fi
            fi
            ;;
        dnf|yum)
            print_status "Installing via Flatpak..."
            if ! command_exists flatpak; then
                if [ "$PKG_MANAGER" = "dnf" ]; then
                    sudo dnf install -y flatpak
                else
                    sudo yum install -y flatpak
                fi
                flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            fi
            flatpak install -y flathub org.raspberrypi.rpi-imager
            IMAGER_CMD="flatpak run org.raspberrypi.rpi-imager"
            ;;
        pacman)
            print_status "Installing via Flatpak..."
            if ! command_exists flatpak; then
                sudo pacman -S --noconfirm flatpak
                flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            fi
            flatpak install -y flathub org.raspberrypi.rpi-imager
            IMAGER_CMD="flatpak run org.raspberrypi.rpi-imager"
            ;;
        zypper)
            print_status "Installing via Flatpak..."
            if ! command_exists flatpak; then
                sudo zypper install -y flatpak
                flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            fi
            flatpak install -y flathub org.raspberrypi.rpi-imager
            IMAGER_CMD="flatpak run org.raspberrypi.rpi-imager"
            ;;
        *)
            print_warning "Unknown package manager. Trying AppImage method..."
            PKG_MANAGER="appimage"
            ;;
    esac
    
    # Fallback to AppImage if package manager installation failed
    if [ -z "$IMAGER_CMD" ] || [ "$PKG_MANAGER" = "appimage" ]; then
        print_status "Downloading AppImage..."
        APPIMAGE_DIR="$HOME/Applications"
        mkdir -p "$APPIMAGE_DIR"
        APPIMAGE_PATH="$APPIMAGE_DIR/rpi-imager.AppImage"
        
        # Download latest AppImage
        IMAGER_URL="https://downloads.raspberrypi.com/imager/imager_latest_amd64.deb"
        # Try to get AppImage URL (this is a fallback - actual URL may vary)
        if command_exists wget; then
            wget -O "$APPIMAGE_PATH" "https://github.com/raspberrypi/rpi-imager/releases/latest/download/rpi-imager_amd64.AppImage" 2>/dev/null || \
            wget -O "$APPIMAGE_PATH" "https://downloads.raspberrypi.com/imager/imager_latest_amd64.AppImage" 2>/dev/null
        elif command_exists curl; then
            curl -L -o "$APPIMAGE_PATH" "https://github.com/raspberrypi/rpi-imager/releases/latest/download/rpi-imager_amd64.AppImage" 2>/dev/null || \
            curl -L -o "$APPIMAGE_PATH" "https://downloads.raspberrypi.com/imager/imager_latest_amd64.AppImage" 2>/dev/null
        else
            print_error "Neither wget nor curl is available. Please install one of them."
            exit 1
        fi
        
        if [ -f "$APPIMAGE_PATH" ]; then
            chmod +x "$APPIMAGE_PATH"
            IMAGER_CMD="$APPIMAGE_PATH"
            print_status "AppImage downloaded and made executable"
        else
            print_error "Failed to download AppImage. Please install Raspberry Pi Imager manually."
            exit 1
        fi
    fi
fi

if [ -z "$IMAGER_CMD" ]; then
    print_error "Could not find or install Raspberry Pi Imager"
    exit 1
fi

# Launch Raspberry Pi Imager
print_status "Launching Raspberry Pi Imager..."
echo
echo "Please use Raspberry Pi Imager to write the OS image to your SD card."
echo "After you're done, close Raspberry Pi Imager and this script will continue."
echo

# Launch in background and get PID
if [[ "$IMAGER_CMD" == *"flatpak"* ]]; then
    $IMAGER_CMD &
else
    $IMAGER_CMD &
fi
IMAGER_PID=$!

# Wait for process to finish
print_status "Waiting for Raspberry Pi Imager to close..."
wait $IMAGER_PID 2>/dev/null || true

echo
print_status "Raspberry Pi Imager has been closed."
echo

# Step 2: Run the bash script to create FAT32 partition
echo "========================================"
echo "Step 1: Creating FAT32 partition"
echo "========================================"
echo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BTRFS_SCRIPT="$SCRIPT_DIR/setup_btrfs_partition.sh"

if [ ! -f "$BTRFS_SCRIPT" ]; then
    print_error "Could not find setup_btrfs_partition.sh"
    print_error "Expected location: $BTRFS_SCRIPT"
    exit 1
fi

print_status "Running setup_btrfs_partition.sh..."
if [ "$EUID" -ne 0 ]; then
    print_warning "Script requires root privileges. Using sudo..."
    sudo bash "$BTRFS_SCRIPT"
else
    bash "$BTRFS_SCRIPT"
fi

if [ $? -ne 0 ]; then
    print_warning "Partition script returned an error."
    print_warning "You may need to manually create the partition or check for errors."
fi

# Step 3: Find the bootfs VFAT partition and copy .sh files
echo
echo "========================================"
echo "Step 2: Copying .sh files to bootfs partition"
echo "========================================"
echo

# Wait a moment for partitions to be recognized
sleep 2

# Find VFAT/FAT32 partition (bootfs)
print_status "Searching for bootfs (VFAT/FAT32) partition..."

BOOTFS_MOUNT=""
BOOTFS_FOUND=0

# Check mounted filesystems first
while IFS= read -r line; do
    if echo "$line" | grep -qiE "(vfat|fat32|msdos)"; then
        MOUNT_POINT=$(echo "$line" | awk '{print $3}')
        # Check if it looks like a bootfs partition
        if [ -d "$MOUNT_POINT/firmware" ] || [ -d "$MOUNT_POINT/boot" ] || [ -f "$MOUNT_POINT/config.txt" ]; then
            BOOTFS_MOUNT="$MOUNT_POINT"
            BOOTFS_FOUND=1
            print_status "Found bootfs partition at: $BOOTFS_MOUNT"
            break
        fi
    fi
done < <(mount | grep -iE "(vfat|fat32|msdos)")

# If not found in mounted, try to find and mount
if [ "$BOOTFS_FOUND" -eq 0 ]; then
    # Look for unmounted VFAT partitions
    for device in /dev/sd*[0-9] /dev/mmcblk*p* /dev/nvme*n*p*; do
        if [ -b "$device" ]; then
            # Check filesystem type
            FSTYPE=$(blkid -s TYPE -o value "$device" 2>/dev/null || true)
            if [ "$FSTYPE" = "vfat" ] || [ "$FSTYPE" = "msdos" ]; then
                # Try to mount temporarily to check
                TEMP_MOUNT=$(mktemp -d)
                if mount "$device" "$TEMP_MOUNT" 2>/dev/null; then
                    if [ -d "$TEMP_MOUNT/firmware" ] || [ -d "$TEMP_MOUNT/boot" ] || [ -f "$TEMP_MOUNT/config.txt" ]; then
                        BOOTFS_MOUNT="$TEMP_MOUNT"
                        BOOTFS_FOUND=1
                        print_status "Found and mounted bootfs partition: $device at $BOOTFS_MOUNT"
                        break
                    else
                        umount "$TEMP_MOUNT" 2>/dev/null || true
                        rmdir "$TEMP_MOUNT" 2>/dev/null || true
                    fi
                else
                    rmdir "$TEMP_MOUNT" 2>/dev/null || true
                fi
            fi
        fi
    done
fi

if [ "$BOOTFS_FOUND" -eq 0 ]; then
    print_error "Could not find bootfs (VFAT) partition."
    echo
    echo "Please make sure:"
    echo "  1. The SD card is inserted"
    echo "  2. The SD card has been written with Raspberry Pi OS"
    echo "  3. The partition is mounted and accessible"
    echo
    echo "Mounted filesystems:"
    mount | grep -E "(vfat|fat32|msdos)" || echo "  (none found)"
    exit 1
fi

echo
print_status "Bootfs partition found: $BOOTFS_MOUNT"
echo

# Create /boot directory if it doesn't exist
if [ ! -d "$BOOTFS_MOUNT/boot" ]; then
    print_status "Creating /boot directory..."
    mkdir -p "$BOOTFS_MOUNT/boot"
fi

# Copy all .sh files to /boot
print_status "Copying .sh files to $BOOTFS_MOUNT/boot/..."
FILES_COPIED=0

for sh_file in "$SCRIPT_DIR"/*.sh; do
    if [ -f "$sh_file" ]; then
        FILENAME=$(basename "$sh_file")
        echo "  Copying $FILENAME..."
        cp "$sh_file" "$BOOTFS_MOUNT/boot/"
        if [ $? -eq 0 ]; then
            chmod +x "$BOOTFS_MOUNT/boot/$FILENAME"
            FILES_COPIED=$((FILES_COPIED + 1))
        else
            print_warning "Failed to copy $FILENAME"
        fi
    fi
done

if [ $FILES_COPIED -eq 0 ]; then
    print_error "No .sh files were copied."
    print_error "Please check that .sh files exist in: $SCRIPT_DIR"
    exit 1
fi

echo
print_status "Successfully copied $FILES_COPIED file(s) to $BOOTFS_MOUNT/boot/"
echo

# Step 4: Append to firmware/firstboot.sh
echo "========================================"
echo "Step 3: Updating firmware/firstboot.sh"
echo "========================================"
echo

FIRSTBOOT_FILE="$BOOTFS_MOUNT/firmware/firstboot.sh"

if [ ! -f "$FIRSTBOOT_FILE" ]; then
    print_status "Creating firmware directory and firstboot.sh..."
    mkdir -p "$BOOTFS_MOUNT/firmware"
    cat > "$FIRSTBOOT_FILE" << 'EOF'
#!/bin/bash
# First boot script
EOF
    chmod +x "$FIRSTBOOT_FILE"
fi

print_status "Appending 'bash /boot/setup.sh' to firstboot.sh..."

# Check if line already exists to avoid duplicates
if ! grep -q "bash /boot/setup.sh" "$FIRSTBOOT_FILE"; then
    echo "bash /boot/setup.sh" >> "$FIRSTBOOT_FILE"
    print_status "Successfully updated firstboot.sh"
else
    print_warning "Line already exists in firstboot.sh, skipping append"
fi

echo
print_status "Verifying firstboot.sh contents:"
echo "----------------------------------------"
cat "$FIRSTBOOT_FILE"
echo "----------------------------------------"
echo

# Unmount if we mounted it
if [[ "$BOOTFS_MOUNT" == /tmp/* ]]; then
    print_status "Unmounting temporary mount..."
    umount "$BOOTFS_MOUNT" 2>/dev/null || true
    rmdir "$BOOTFS_MOUNT" 2>/dev/null || true
fi

echo "========================================"
print_status "Setup completed successfully!"
echo "========================================"
echo
echo "Summary:"
echo "  - FAT32 partition created (if needed)"
echo "  - .sh files copied to bootfs/boot/"
echo "  - firstboot.sh updated to run setup.sh"
echo
echo "The SD card is ready to use!"
echo

