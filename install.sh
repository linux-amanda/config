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
   log_error "Skrip ini harus dijalankan sebagai root (gunakan sudo atau login sebagai root)."
   exit 1
fi

if [[ ! -d /sys/firmware/efi ]]; then
    log_error "Sistem tidak dijalankan dalam mode UEFI! Skrip ini memerlukan mode UEFI."
    exit 1
fi

show_header

# --- PARTITION LISTING ---
log_info "Menampilkan daftar partisi yang tersedia di sistem Anda:"
echo -e "${YELLOW}"
lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINTS
echo -e "${NC}"

# --- INTERACTIVE USER INPUTS ---
log_info "Silakan masukkan detail partisi dengan teliti (contoh: /dev/sda1 atau /dev/nvme0n1p1):"
echo

read -p "  1. Partisi Boot/EFI Amanda OS (Akan diformat ke FAT32): " boot
while [[ -z "$boot" || ! -b "$boot" ]]; do
    log_error "Partisi '$boot' tidak valid."
    read -p "  1. Partisi Boot/EFI Amanda OS: " boot
done

read -p "  2. Partisi Root Amanda OS (Akan Di-ENKRIPSI dengan LUKS): " root
while [[ -z "$root" || ! -b "$root" ]]; do
    log_error "Partisi '$root' tidak valid."
    read -p "  2. Partisi Root Amanda OS: " root
done

read -p "  3. Partisi Home Amanda OS (Akan diformat ke EXT4): " home
while [[ -z "$home" || ! -b "$home" ]]; do
    log_error "Partisi '$home' tidak valid."
    read -p "  3. Partisi Home Amanda OS: " home
done

read -p "  4. Partisi Swap Amanda OS (Akan diformat ke Swap): " swap
while [[ -z "$swap" || ! -b "$swap" ]]; do
    log_error "Partisi '$swap' tidak valid."
    read -p "  4. Partisi Swap Amanda OS: " swap
done

echo
log_info "Konfigurasi Enkripsi Partisi Root (LUKS):"
read -sp "  Masukkan Passphrase Enkripsi Root: " luks_pass
echo
while [[ -z "$luks_pass" ]]; do
    log_error "Passphrase Enkripsi tidak boleh kosong!"
    read -sp "  Masukkan Passphrase Enkripsi Root: " luks_pass
    echo
done

echo
log_info "Konfigurasi Identitas & Kredensial Pengguna:"
read -p "  Masukkan Username baru: " username
while [[ -z "$username" ]]; do
    log_error "Username tidak boleh kosong!"
    read -p "  Masukkan Username baru: " username
done

read -p "  Masukkan Hostname komputer: " hostname
while [[ -z "$hostname" ]]; do
    log_error "Hostname tidak boleh kosong!"
    read -p "  Masukkan Hostname komputer: " hostname
done

read -sp "  Masukkan Password akun $username (dan root): " pw
echo
while [[ -z "$pw" ]]; do
    log_error "Password tidak boleh kosong!"
    read -sp "  Masukkan Password akun $username (dan root): " pw
    echo
done

# --- CONFIRMATION SUMMARY ---
show_header
log_warning "PERHATIAN! Tindakan berikut akan menghapus data pada partisi terpilih:"
echo -e "  - ${RED}Amanda OS Boot Partition:${NC} $boot (Akan DI-FORMAT menjadi FAT32)"
echo -e "  - ${RED}Root Partition (ENCRYPTION):${NC} $root (Akan DI-ENKRIPSI LUKS2 & Format EXT4)"
echo -e "  - ${RED}Home Partition:${NC}           $home (Akan DI-FORMAT)"
echo -e "  - ${RED}Swap Partition:${NC}           $swap (Akan DI-FORMAT)"
echo
echo -e "  - ${CYAN}Username:${NC}                  $username"
echo -e "  - ${CYAN}Hostname:${NC}                  $hostname"
echo

read -p "Apakah Anda yakin ingin melanjutkan instalasi? (ketik 'yes' untuk konfirmasi): " confirm
if [[ "$confirm" != "yes" ]]; then
    log_info "Instalasi dibatalkan oleh pengguna."
    exit 0
fi

# --- HARDWARE AUTO-DETECTION ---
show_header
log_info "Mendeteksi perangkat keras (Hardware Auto-Detection)..."

ucodes=""
gpu_module=""
firms="linux-firmware"

# CPU Detection
cpu_vendor=$(lscpu | grep -i "Vendor ID:" | awk '{print $3}')
if [[ "$cpu_vendor" == *"Intel"* ]]; then
    ucodes="intel-ucode"
    gpu_module="i915"
    log_success "Prosesor Intel dideteksi. Menggunakan microcode: $ucodes"
elif [[ "$cpu_vendor" == *"AMD"* ]]; then
    ucodes="amd-ucode"
    gpu_module="amdgpu"
    log_success "Prosesor AMD dideteksi. Menggunakan microcode: $ucodes"
else
    log_warning "Prosesor tidak dikenal. Tidak memasang microcode tambahan."
fi

firms="$firms sof-firmware alsa-firmware"

# --- 1. FORMAT & ENCRYPT DISK ---
log_info "Memulai proses Enkripsi dan Pemformatan..."

log_info "Mengenkripsi partisi Root ($root) menggunakan LUKS2..."
echo -n "$luks_pass" | cryptsetup luksFormat --type luks2 --verify-passphrase "$root" -

log_info "Membuka partisi terenkripsi LUKS..."
echo -n "$luks_pass" | cryptsetup open "$root" cryptroot -

log_info "Format Root terenkripsi (/dev/mapper/cryptroot): ext4"
mkfs.ext4 -F -b 4096 /dev/mapper/cryptroot

log_info "Format Boot Amanda OS: $boot (FAT32)"
mkfs.vfat -F32 -n AMANDA_BOOT "$boot"

log_info "Format Home: $home (ext4)"
mkfs.ext4 -F -b 4096 "$home"

log_info "Format Swap: $swap"
mkswap -f "$swap"

# Ambil UUID dari partisi root terenkripsi asli untuk konfigurasi GRUB
luks_uuid=$(blkid -s UUID -o value "$root")

log_success "Pemformatan dan Enkripsi selesai!"
sleep 2

# --- 2. MOUNTING ---
log_info "Memasang (mounting) partisi..."

mount /dev/mapper/cryptroot /mnt

mkdir -p /mnt/boot
mount -o uid=0,gid=0,fmask=0077,dmask=0077 "$boot" /mnt/boot

mkdir -p /mnt/home
mount "$home" /mnt/home

swapon "$swap"

log_success "Semua partisi berhasil terpasang!"
sleep 2

# --- 3. PACSTRAP (INSTALL BASE PACKAGES + PLYMOUTH + CRYPTSETUP) ---
log_info "Memasang paket dasar Amanda OS..."

pacstrap -K /mnt base base-devel linux-lts linux-lts-headers $firms $ucodes \
    networkmanager network-manager-applet firewalld git wget neovim \
    efibootmgr os-prober grub ntfs-3g sbctl iptables-nft bash-completion cryptsetup plymouth archlinux-keyring --noconfirm

# Generate FSTAB
log_info "Membuat file fstab..."
genfstab -U /mnt > /mnt/etc/fstab

log_success "Pemasangan paket dasar dan konfigurasi fstab selesai!"
sleep 2

# --- 4. SYSTEM CONFIGURATION (CHROOT) ---
log_info "Memasuki chroot untuk konfigurasi sistem..."

arch-chroot /mnt /bin/bash <<EOF
set -e

# --- 4.1. Timezone & Locale ---
echo "Mengatur Timezone (Asia/Jakarta)..."
ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
hwclock --systohc

echo "Mengatur Locale..."
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# --- 4.2. Hostname ---
echo "Mengatur Hostname..."
echo "$hostname" > /etc/hostname

# --- 4.3. Users & Groups ---
echo "Membuat pengguna baru ($username)..."
useradd -m -G wheel -s /bin/bash "$username"
echo "$username:$pw" | chpasswd
echo "root:$pw" | chpasswd

# --- 4.4. Sudoers Configuration ---
echo "Mengonfigurasi Sudoers..."
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-installer-wheel
chmod 440 /etc/sudoers.d/10-installer-wheel

# --- 4.5. Services Activation ---
echo "Mengaktifkan layanan sistem dasar..."
systemctl enable NetworkManager
systemctl enable firewalld

# --- 4.6. Configure mkinitcpio (Systemd + Plymouth + sd-encrypt) ---
echo "Mengonfigurasi HOOKS dan MODULES untuk Plymouth & sd-encrypt..."
if [[ -n "$gpu_module" ]]; then
    sed -i "s/^MODULES=()/MODULES=($gpu_module)/" /etc/mkinitcpio.conf
fi

sed -i 's/^HOOKS=.*/HOOKS=(base systemd plymouth autodetect kms block sd-encrypt filesystems keyboard fsck)/' /etc/mkinitcpio.conf

echo "Membuat RAM Disk awal (mkinitcpio)..."
mkinitcpio -P

# --- 4.7. Plymouth Theme Setup ---
echo "Mengatur tema grafis Plymouth..."
plymouth-set-default-theme -R bgrt

# --- 4.8. GRUB Setup (sd-encrypt & Plymouth arguments) ---
echo "Memasang GRUB Bootloader ke Partisi Boot Amanda OS..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=AmandaOS --modules="tpm" --disable-shim-lock

echo "Mengonfigurasi parameter Kernel..."
sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="AmandaOS"/' /etc/default/grub
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="rd.luks.name=$luks_uuid=cryptroot root=\/dev\/mapper\/cryptroot quiet splash loglevel=3"/' /etc/default/grub
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub

# Buat konfigurasi GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# --- 4.9. Secure Boot (sbctl) ---
#echo "Mengonfigurasi Secure Boot menggunakan sbctl..."
#sbctl create-keys
#sbctl enroll-keys -m -f

#echo "Menandatangani berkas booting..."
#sbctl sign --save /boot/EFI/AmandaOS/grubx64.efi
#sbctl sign --save /boot/vmlinuz-linux-lts

EOF

log_success "Konfigurasi di dalam chroot berhasil diselesaikan!"
sleep 2

# --- 5. KDE PLASMA PACKAGE INSTALLATION ---
log_info "Memasang Lingkungan Desktop KDE Plasma..."
arch-chroot /mnt pacman -S plasma-meta sddm konsole dolphin firefox pipewire pipewire-jack pipewire-alsa pipewire-pulse wireplumber pamixer ffmpegthumbs plymouth-kcm --noconfirm || arch-chroot /mnt pacman -S plasma-meta sddm konsole dolphin pipewire pipewire-jack pipewire-alsa pipewire-pulse wireplumber pamixer ffmpegthumbs --noconfirm

log_info "Mengaktifkan Display Manager (SDDM)..."
arch-chroot /mnt systemctl enable sddm

log_success "Instalasi Lingkungan Desktop KDE Plasma selesai!"
sleep 2

# --- 6. CONFIG WALLPAPER PLASMA ---
log_info "Memasang Wallpaper default"
rm /mnt/usr/share/wallpapers/Next/contents/images/*
cp -r amanda/* /mnt 
arch-chroot /mnt sed -i '/favoritesPortedToKAstats=true/a icon=\/usr\/share\/pixmaps\/amanda-logo.png' /home/$username/.config/plasma-org.kde.plasma.desktop-appletsrc

# --- 7. REMOVING PROVISIONING CONFIG
rm -fr config

# --- CLEAN UP & FINISH ---
show_header
log_success "CONGRATULATIONS! Pemasangan Amanda OS (LUKS Encrypted + Plymouth + KDE) telah selesai!"
log_info "Anda dapat me-reboot komputer Anda sekarang."
echo
