#!/usr/bin/env bash

# ==============================================================================
# Amanda OS Installation Script (Single Boot Standalone + LUKS Encrypted + Plymouth)
# Refactored for visual clarity, safety, LUKS encryption, and KDE Plasma.
# ==============================================================================

# Exit immediately if a command exits with a non-zero status
set -e

# --- COLOR DEFINITIONS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- LOGGING FUNCTIONS ---
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_header() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${CYAN}                        AMANDA OS INSTALLER                           ${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo
}

# --- PRE-FLIGHT CHECKS ---
if [[ $EUID -ne 0 ]]; then
   log_error "This script must run in a archiso"
   exit 1
fi

if [[ ! -d /sys/firmware/efi ]]; then
    log_error "System is not in UEFI mode! This script needed UEFI mode."
    exit 1
fi

show_header

# --- PARTITION LISTING ---
log_info "Displaying the list of available partitions on your system:"
echo -e "${YELLOW}"
lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINTS
echo -e "${NC}"

# --- INTERACTIVE USER INPUTS ---
log_info "Please enter the partition path carefully (e.g., /dev/sda1 or /dev/nvme0n1p1):"
echo

read -p "  1. Amanda OS Boot/EFI Partition (will be formatted as FAT32): " boot
while [[ -z "$boot" || ! -b "$boot" ]]; do
    log_error "Partition '$boot' is invalid."
    read -p "  1. Amanda OS Boot/EFI Partition: " boot
done

read -p "  2. Amanda OS Root Partition (will be formatted as EXT4): " root
while [[ -z "$root" || ! -b "$root" ]]; do
    log_error "Partition '$root' is invalid."
    read -p "  2. Amanda OS Root Partition: " root
done

read -p "  3. Home Partition for Amanda OS (will be formatted as EXT4): " home
while [[ -z "$home" || ! -b "$home" ]]; do
    log_error "Partition '$home' is invalid."
    read -p "  3. Home Partition for Amanda OS: " home
done

read -p "  4. Swap Partition for Amanda OS (will be formatted as swap): " swap
while [[ -z "$swap" || ! -b "$swap" ]]; do
    log_error "Partition '$swap' is invalid."
    read -p "  4. Swap Partition for Amanda OS: " swap
done

echo
log_info "User Identity & Credentials Configuration:"
read -p "  Enter a new username: " username
while [[ -z "$username" ]]; do
    log_error "Username cannot be empty!"
    read -p "  Enter a new username: " username
done

read -p "  Enter the computer hostname: " hostname
while [[ -z "$hostname" ]]; do
    log_error "Hostname cannot be empty!"
    read -p "  Enter the computer hostname: " hostname
done

read -sp "  Enter the password for $username (and root): " pw
echo
while [[ -z "$pw" ]]; do
    log_error "Password cannot be empty!"
    read -sp "  Enter the password for the $USERNAME and root accounts: " pw
    echo
done

echo
log_info "Displaying available timezone regions:"
echo -e "${YELLOW}"
ls /usr/share/zoneinfo
echo -e "${NC}"


read -rp "Select region example (Asia): " region

echo
log_info "Displaying available timezones for region '$region':"
echo -e "${YELLOW}"
ls /usr/share/zoneinfo/$region
echo -e "${NC}"


read -rp "Select country example (Jakarta): " country


timezone="$region/$country"

echo
log_info "Displaying available locales..."


echo -e "${YELLOW}"
cat /etc/locale.gen
echo -e "${NC}"


read -rp "Select locale (example: en_US.UTF-8): " locale
clear


# --- CONFIRMATION SUMMARY ---
show_header
log_warning "WARNING! The following actions will erase all data on the selected partitions:"
echo -e "  - ${RED}Amanda OS Boot Partition:${NC}     $boot (will be formatted as FAT32)"
echo -e "  - ${RED}Root Partition (Encryption):${NC}  $root (will be formatted as EXT4)"
echo -e "  - ${RED}Home Partition:${NC}               $home (will be formatted as EXT4)"
echo -e "  - ${RED}Swap Partition:${NC}               $swap (will be formatted as swap)"
echo
echo -e "  - ${CYAN}Username:${NC}                 $username"
echo -e "  - ${CYAN}Hostname:${NC}                 $hostname"
echo -e "  - ${CYAN}timezone:${NC}                 $timezone"
echo -e "  - ${CYAN}locale:${NC}                   $locale"

read -rp "Are you sure you want to continue with the installation? (type 'yes' to confirm): " confirm

if [[ "$confirm" != "yes" ]]; then
    log_info "Installation canceled by the user."
    exit 0
fi

# --- HARDWARE AUTO-DETECTION ---
show_header
log_info "Detecting hardware (automatic hardware detection)..."

ucodes=""
gpu_module=""
firms="linux-firmware"

# CPU Detection
cpu_vendor=$(lscpu | grep -i "Vendor ID:" | awk '{print $3}')
if [[ "$cpu_vendor" == *"Intel"* ]]; then
    ucodes="intel-ucode"
    gpu_module="i915"
    log_success "Intel processor detected. Using microcode: $ucodes"
elif [[ "$cpu_vendor" == *"AMD"* ]]; then
    ucodes="amd-ucode"
    gpu_module="amdgpu"
    log_success "AMD CPU detected. Using microcode: $ucodes"
else
    log_warning "Unknown processor. No additional microcode will be installed."
fi

firms="$firms sof-firmware alsa-firmware"

# --- 1. FORMAT & ENCRYPT DISK ---
log_info "Formatting root partition ($root): ext4"
mkfs.ext4 -F -b 4096 $root

log_info "Formatting Amanda OS boot partition: $boot (FAT32)"
mkfs.vfat -F32 -n BOOT "$boot"

log_info "Formatting home partition: $home (ext4)"
mkfs.ext4 -F -b 4096 "$home"

log_info "Formatting swap partition: $swap"
mkswap -f "$swap"

# Ambil UUID dari partisi root terenkripsi asli untuk konfigurasi GRUB
root_uuid=$(blkid -s UUID -o value "$root")

log_success "Formatting and encryption completed successfully!"
sleep 2

# --- 2. MOUNTING ---
log_info "Mounting partitions..."

mount $root /mnt

mkdir -p /mnt/boot
mount -o uid=0,gid=0,fmask=0077,dmask=0077 "$boot" /mnt/boot

mkdir -p /mnt/home
mount "$home" /mnt/home

swapon "$swap"

log_success "All partitions mounted successfully!"
sleep 2

# --- 3. PACSTRAP (INSTALL BASE PACKAGES + PLYMOUTH + CRYPTSETUP) ---
log_info "Installing Amanda OS base packages..."

pacstrap -K /mnt base base-devel linux-lts linux-lts-headers $firms $ucodes \
    networkmanager network-manager-applet firewalld git wget neovim \
    efibootmgr os-prober grub ntfs-3g sbctl iptables-nft bash-completion plymouth archlinux-keyring \
    plasma-meta sddm konsole dolphin firefox pipewire pipewire-jack pipewire-alsa pipewire-pulse wireplumber pamixer ffmpegthumbs plymouth-kcm --noconfirm

# Generate FSTAB
log_info "Generating fstab file..."
genfstab -U /mnt > /mnt/etc/fstab

log_success "Base package installation and fstab configuration completed successfully!"
sleep 2

# --- 4. SYSTEM CONFIGURATION (CHROOT) ---
log_info "Entering chroot for system configuration..."

arch-chroot /mnt /bin/bash <<EOF
set -e

# --- 4.1. Timezone ---
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

# --- 4.2. Locale
sed -i "s/^#${locale}/${locale}/" /etc/locale.gen

locale-gen

echo "LANG=${locale}" > /etc/locale.conf

# --- 4.3. Hostname ---
echo "Configuring hostname..."

echo "$hostname" > /etc/hostname

# --- 4.4. Users & Groups ---
echo "Creating new user ($username)..."

useradd -m -G wheel -s /bin/bash "$username"

echo "$username:$pw" | chpasswd
echo "root:$pw" | chpasswd

# --- 4.5. Sudoers Configuration ---
echo "Configuring sudoers..."
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-installer-wheel
chmod 440 /etc/sudoers.d/10-installer-wheel

# --- 4.6. Services Activation ---
echo "Enabling essential system services..."
systemctl enable NetworkManager
systemctl enable firewalld

# --- 4.6. Configure mkinitcpio (Systemd + Plymouth + sd-encrypt) ---
echo "Configuring HOOKS and MODULES for Plymouth and sd-encrypt..."
if [[ -n "$gpu_module" ]]; then
    sed -i "s/^MODULES=()/MODULES=($gpu_module)/" /etc/mkinitcpio.conf
fi

sed -i 's/^HOOKS=.*/HOOKS=(base udev plymouth autodetect kms block filesystems keyboard fsck)/' /etc/mkinitcpio.conf

echo "Generating initial RAM disk (mkinitcpio)..."
mkinitcpio -P

# --- 4.7. Plymouth Theme Setup ---
echo "Configuring Plymouth graphical theme..."
plymouth-set-default-theme -R bgrt

# --- 4.8. GRUB Setup (sd-encrypt & Plymouth arguments) ---
echo "Installing GRUB bootloader to Amanda OS boot partition..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=AmandaOS --modules="tpm" --disable-shim-lock

echo "Configuring kernel parameters..."
sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="AmandaOS"/' /etc/default/grub
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="root=UUID='"$root_uuid"' quiet splash loglevel=3"/' /etc/default/grub
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub

# Buat konfigurasi GRUB
grub-mkconfig -o /boot/grub/grub.cfg

EOF

log_success "Chroot system configuration completed successfully!"
sleep 2

# --- 5. KDE PLASMA PACKAGE INSTALLATION ---
log_info "Enabling Display Manager (SDDM)..."
arch-chroot /mnt systemctl enable sddm

log_success "KDE Plasma desktop environment installation completed successfully!"
sleep 2

# --- 6. CONFIG WALLPAPER PLASMA ---
log_info "Installing default wallpaper..."
rm /mnt/usr/share/wallpapers/Next/contents/images/*
rm /mnt/usr/share/plasma/look-and-feel/org.kde.breeze.desktop/contents/splash/images/*
cp -r amanda/* /mnt 

# --- 7. LOGO DEFAULT ---
mkdir -p /mnt/home/$username/.config/
cat << 'EOF' > /mnt/home/$username/.config/plasma-org.kde.plasma.desktop-appletsrc
[ActionPlugins][0]
RightButton;NoModifier=org.kde.contextmenu

[ActionPlugins][1]
RightButton;NoModifier=org.kde.contextmenu

[Containments][1]
activityId=dd56e143-b347-4adb-b793-844f5cfb5878
formfactor=0
immutability=1
lastScreen=0
location=0
plugin=org.kde.plasma.folder
wallpaperplugin=org.kde.image

[Containments][2]
activityId=
formfactor=2
immutability=1
lastScreen=0
location=4
plugin=org.kde.panel
wallpaperplugin=org.kde.image

[Containments][2][Applets][21]
immutability=1
plugin=org.kde.plasma.digitalclock

[Containments][2][Applets][21][Configuration]
popupHeight=400
popupWidth=560

[Containments][2][Applets][21][Configuration][Appearance]
fontWeight=400

[Containments][2][Applets][22]
immutability=1
plugin=org.kde.plasma.showdesktop

[Containments][2][Applets][3]
immutability=1
plugin=org.kde.plasma.kickoff

[Containments][2][Applets][3][Configuration]
popupHeight=509
popupWidth=647

[Containments][2][Applets][3][Configuration][General]
favoritesPortedToKAstats=true
icon=/usr/share/pixmaps/amanda-logo.png

[Containments][2][Applets][4]
immutability=1
plugin=org.kde.plasma.pager

[Containments][2][Applets][5]
immutability=1
plugin=org.kde.plasma.icontasks

[Containments][2][Applets][6]
immutability=1
plugin=org.kde.plasma.marginsseparator

[Containments][2][Applets][7]
activityId=
formfactor=0
immutability=1
lastScreen=-1
location=0
plugin=org.kde.plasma.systemtray
popupHeight=432
popupWidth=432
wallpaperplugin=org.kde.image

[Containments][2][Applets][7][Applets][10]
immutability=1
plugin=org.kde.plasma.manage-inputmethod

[Containments][2][Applets][7][Applets][11]
immutability=1
plugin=org.kde.plasma.volume

[Containments][2][Applets][7][Applets][11][Configuration][General]
migrated=true

[Containments][2][Applets][7][Applets][12]
immutability=1
plugin=org.kde.plasma.keyboardlayout

[Containments][2][Applets][7][Applets][13]
immutability=1
plugin=org.kde.plasma.cameraindicator

[Containments][2][Applets][7][Applets][14]
immutability=1
plugin=org.kde.plasma.keyboardindicator

[Containments][2][Applets][7][Applets][15]
immutability=1
plugin=org.kde.plasma.weather

[Containments][2][Applets][7][Applets][16]
immutability=1
plugin=org.kde.plasma.printmanager

[Containments][2][Applets][7][Applets][17]
immutability=1
plugin=org.kde.plasma.devicenotifier

[Containments][2][Applets][7][Applets][18]
immutability=1
plugin=org.kde.kscreen

[Containments][2][Applets][7][Applets][19]
immutability=1
plugin=org.kde.plasma.clipboard

[Containments][2][Applets][7][Applets][20]
immutability=1
plugin=org.kde.plasma.networkmanagement

[Containments][2][Applets][7][Applets][23]
immutability=1
plugin=org.kde.plasma.battery

[Containments][2][Applets][7][Applets][24]
immutability=1
plugin=org.kde.plasma.brightness

[Containments][2][Applets][7][Applets][8]
immutability=1
plugin=org.kde.plasma.vault

[Containments][2][Applets][7][Applets][9]
immutability=1
plugin=org.kde.plasma.notifications

[Containments][2][Applets][7][General]
extraItems=org.kde.plasma.vault,org.kde.plasma.notifications,org.kde.plasma.manage-inputmethod,org.kde.plasma.brightness,org.kde.plasma.volume,org.kde.plasma.keyboardlayout,org.kde.plasma.cameraindicator,org.kde.plasma.keyboardindicator,org.kde.plasma.bluetooth,org.kde.plasma.weather,org.kde.plasma.battery,org.kde.plasma.printmanager,org.kde.plasma.devicenotifier,org.kde.kscreen,org.kde.plasma.clipboard,org.kde.plasma.networkmanagement,org.kde.plasma.mediacontroller
knownItems=org.kde.plasma.vault,org.kde.plasma.notifications,org.kde.plasma.manage-inputmethod,org.kde.plasma.brightness,org.kde.plasma.volume,org.kde.plasma.keyboardlayout,org.kde.plasma.cameraindicator,org.kde.plasma.keyboardindicator,org.kde.plasma.bluetooth,org.kde.plasma.weather,org.kde.plasma.battery,org.kde.plasma.printmanager,org.kde.plasma.devicenotifier,org.kde.kscreen,org.kde.plasma.clipboard,org.kde.plasma.networkmanagement,org.kde.plasma.mediacontroller

[Containments][2][General]
AppletOrder=3;4;5;6;7;21;22

[ScreenMapping]
itemsOnDisabledScreens=
screenMapping=
EOF

arch-chroot /mnt chown -R $username:$username /home/$username/.config


# --- 8. REMOVING PROVISIONING CONFIG
rm -fr amanda

# --- CLEAN UP & FINISH ---
show_header
log_success "CONGRATULATIONS! Amanda OS installation (LUKS Encrypted + Plymouth + KDE) has been completed successfully!"
log_info "You can reboot your computer now."
echo
