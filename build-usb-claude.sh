#!/bin/bash
# =============================================================================
# USB-Claude - Build Script
# EFC Informatique - Station de travail MSP portable
#
# Construit une ISO Debian 13 live bootable avec:
# - Cinnamon desktop + outils MSP complets
# - Claude Code + VS Codium + Git/GitHub CLI
# - Active Directory, reseau, disques, recovery
# - Persistance sur cle USB (overlay /home, /etc)
# - Auto-detection reseau (WiFi, Ethernet, Hotspot)
#
# Usage: sudo ./build-usb-claude.sh [--clean] [--skip-debootstrap]
#
# Auteur: Erick Fortin (erick@efcinfo.com)
# Date: 2026-03-24
# =============================================================================
set -e

# === CONFIGURATION ===
VERSION="1.0"
CODENAME="trixie"
ARCH="amd64"
CHROOT_DIR="/projets/usb-claude-chroot"
BUILD_DIR="/projets/usb-claude-build"
ISO_OUTPUT="/projets/projet-reseau/usb-claude/usb-claude-${VERSION}.iso"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MIRROR="http://deb.debian.org/debian"
HOSTNAME="usb-claude"
USERNAME="erick"
LOCALE="fr_CA.UTF-8"
TIMEZONE="America/Montreal"
KEYBOARD="ca"

# Couleurs pour output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# === FONCTIONS UTILITAIRES ===
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERREUR]${NC} $1"; }
log_step()  { echo -e "\n${CYAN}========================================${NC}"; echo -e "${CYAN}  ETAPE: $1${NC}"; echo -e "${CYAN}========================================${NC}"; }

cleanup_chroot() {
    log_info "Nettoyage des montages chroot..."
    for mp in proc/sys/fs/binfmt_misc proc sys dev/pts dev run; do
        mountpoint -q "${CHROOT_DIR}/${mp}" 2>/dev/null && umount -lf "${CHROOT_DIR}/${mp}" 2>/dev/null || true
    done
}

trap cleanup_chroot EXIT

# === ARGUMENTS ===
CLEAN=false
SKIP_DEBOOTSTRAP=false
for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN=true ;;
        --skip-debootstrap) SKIP_DEBOOTSTRAP=true ;;
        --help|-h)
            echo "Usage: sudo $0 [--clean] [--skip-debootstrap]"
            echo "  --clean            Nettoyer le build precedent avant de commencer"
            echo "  --skip-debootstrap Sauter le debootstrap (reutiliser le chroot existant)"
            exit 0
            ;;
    esac
done

# === VERIFICATIONS ===
log_step "Verification des pre-requis"

if [ "$(id -u)" -ne 0 ]; then
    log_error "Ce script doit etre execute en root (sudo)"
    exit 1
fi

REQUIRED_PKGS="debootstrap squashfs-tools xorriso grub-efi-amd64-bin grub-pc-bin mtools dosfstools"
MISSING=""
for pkg in $REQUIRED_PKGS; do
    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        MISSING="$MISSING $pkg"
    fi
done

if [ -n "$MISSING" ]; then
    log_info "Installation des paquets manquants:$MISSING"
    apt-get update
    apt-get install -y $MISSING
fi

DISK_FREE=$(df /projets --output=avail -B1G | tail -1 | tr -d ' ')
if [ "$DISK_FREE" -lt 15 ]; then
    log_error "Espace disque insuffisant dans /projets (${DISK_FREE}G disponible, 15G requis)"
    exit 1
fi

log_info "Pre-requis OK - ${DISK_FREE}G disponibles"

# === NETTOYAGE (optionnel) ===
if $CLEAN; then
    log_step "Nettoyage du build precedent"
    cleanup_chroot
    rm -rf "$CHROOT_DIR" "$BUILD_DIR"
    log_info "Nettoyage termine"
fi

# === PHASE 1: DEBOOTSTRAP ===
if ! $SKIP_DEBOOTSTRAP || [ ! -d "$CHROOT_DIR/bin" ]; then
    log_step "Debootstrap Debian 13 (${CODENAME})"

    if [ -d "$CHROOT_DIR" ]; then
        cleanup_chroot
        rm -rf "$CHROOT_DIR"
    fi

    log_info "Telechargement du systeme de base..."
    debootstrap --arch="$ARCH" --variant=minbase \
        --include=apt,locales,sudo,systemd,systemd-sysv,dbus,linux-image-amd64 \
        "$CODENAME" "$CHROOT_DIR" "$MIRROR"

    log_info "Debootstrap termine"
else
    log_info "Reutilisation du chroot existant (--skip-debootstrap)"
fi

# === MONTAGE DU CHROOT ===
log_step "Montage du chroot"
mount --bind /proc "$CHROOT_DIR/proc"
mount --bind /sys "$CHROOT_DIR/sys"
mount --bind /dev "$CHROOT_DIR/dev"
mount --bind /dev/pts "$CHROOT_DIR/dev/pts"
mount -t tmpfs tmpfs "$CHROOT_DIR/run"

# Copier resolv.conf pour avoir Internet dans le chroot
cp /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"

# === PHASE 2: CONFIGURATION DES DEPOTS ===
log_step "Configuration des depots APT"

cat > "$CHROOT_DIR/etc/apt/sources.list" << EOF
deb $MIRROR $CODENAME main contrib non-free non-free-firmware
deb $MIRROR ${CODENAME}-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security ${CODENAME}-security main contrib non-free non-free-firmware
EOF

chroot "$CHROOT_DIR" apt-get update

# === PHASE 3: INSTALLATION DES PAQUETS ===
log_step "Installation des paquets (Desktop Environment)"

# Eviter les dialogues interactifs
export DEBIAN_FRONTEND=noninteractive

chroot "$CHROOT_DIR" apt-get install -y --no-install-recommends \
    cinnamon cinnamon-desktop-environment \
    lightdm lightdm-gtk-greeter \
    nemo nemo-fileroller \
    gnome-terminal \
    fonts-noto fonts-liberation2 \
    xserver-xorg xserver-xorg-video-all \
    pulseaudio pavucontrol \
    dconf-cli

log_step "Installation des firmwares (MAX compatibilite reseau)"

chroot "$CHROOT_DIR" apt-get install -y --no-install-recommends \
    firmware-linux-nonfree \
    firmware-iwlwifi \
    firmware-realtek \
    firmware-brcm80211 \
    firmware-atheros \
    firmware-misc-nonfree \
    firmware-amd-graphics \
    firmware-intel-sound \
    2>/dev/null || log_warn "Certains firmwares non disponibles, on continue..."

log_step "Installation des outils reseau"

chroot "$CHROOT_DIR" apt-get install -y --no-install-recommends \
    network-manager network-manager-gnome wpasupplicant \
    nmap wireshark tcpdump traceroute mtr-tiny iperf3 \
    arp-scan netdiscover ethtool wavemon \
    dnsutils net-tools iproute2 curl wget socat \
    avahi-utils bridge-utils vlan \
    iputils-ping

log_step "Installation des outils Active Directory"

chroot "$CHROOT_DIR" apt-get install -y --no-install-recommends \
    samba-common-bin ldap-utils adcli realmd \
    sssd sssd-tools krb5-user winbind \
    libnss-winbind libpam-winbind \
    2>/dev/null || log_warn "Certains paquets AD non disponibles, on continue..."

log_step "Installation des outils Remote Access"

chroot "$CHROOT_DIR" apt-get install -y --no-install-recommends \
    remmina remmina-plugin-rdp remmina-plugin-vnc \
    tigervnc-viewer \
    openssh-client openssh-server tmux screen

log_step "Installation des outils disques & recovery"

chroot "$CHROOT_DIR" apt-get install -y --no-install-recommends \
    gparted parted gdisk \
    testdisk gddrescue smartmontools hdparm \
    ntfs-3g exfatprogs dosfstools e2fsprogs \
    btrfs-progs xfsprogs \
    chntpw efibootmgr

log_step "Installation des outils de developpement"

chroot "$CHROOT_DIR" apt-get install -y --no-install-recommends \
    git python3 python3-pip python3-venv \
    nodejs npm vim nano \
    build-essential cmake jq

log_step "Installation des outils monitoring & fichiers"

chroot "$CHROOT_DIR" apt-get install -y --no-install-recommends \
    htop btop iotop nethogs bmon \
    sysstat lsof fio strace \
    mc ranger rsync rclone \
    smbclient cifs-utils nfs-common sshfs \
    p7zip-full unzip zip

log_step "Installation des outils web, VPN, securite, systeme"

chroot "$CHROOT_DIR" apt-get install -y --no-install-recommends \
    firefox-esr \
    wireguard-tools openvpn \
    gnupg openssl ca-certificates cryptsetup \
    sudo bash-completion locales console-setup \
    usbutils pciutils lshw hwinfo inxi dmidecode \
    acpi powertop \
    dialog whiptail ncdu tree \
    live-boot live-config live-config-systemd

# === PHASE 4: CONFIGURATION DU SYSTEME ===
log_step "Configuration du systeme"

# Hostname
echo "$HOSTNAME" > "$CHROOT_DIR/etc/hostname"
cat > "$CHROOT_DIR/etc/hosts" << EOF
127.0.0.1   localhost
127.0.1.1   $HOSTNAME
EOF

# Locales
chroot "$CHROOT_DIR" bash -c "
    sed -i 's/# fr_CA.UTF-8/fr_CA.UTF-8/' /etc/locale.gen
    sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
    locale-gen
    update-locale LANG=${LOCALE}
"

# Timezone
chroot "$CHROOT_DIR" ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
echo "$TIMEZONE" > "$CHROOT_DIR/etc/timezone"

# Clavier
cat > "$CHROOT_DIR/etc/default/keyboard" << EOF
XKBMODEL="pc105"
XKBLAYOUT="${KEYBOARD}"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF

# Creer l'utilisateur
chroot "$CHROOT_DIR" bash -c "
    # Creer les groupes manquants si necessaire
    for grp in wireshark netdev bluetooth plugdev; do
        getent group \$grp >/dev/null 2>&1 || groupadd \$grp 2>/dev/null || true
    done
    # Creer l'utilisateur
    id $USERNAME >/dev/null 2>&1 || useradd -m -s /bin/bash $USERNAME
    # Ajouter aux groupes
    for grp in sudo audio video plugdev netdev bluetooth cdrom floppy dialout wireshark; do
        usermod -aG \$grp $USERNAME 2>/dev/null || true
    done
    echo '${USERNAME} ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/${USERNAME}
    chmod 440 /etc/sudoers.d/${USERNAME}
    # Pas de mot de passe pour le live
    passwd -d ${USERNAME} 2>/dev/null || true
"

# LightDM auto-login
mkdir -p "$CHROOT_DIR/etc/lightdm/lightdm.conf.d"
cat > "$CHROOT_DIR/etc/lightdm/lightdm.conf.d/50-autologin.conf" << EOF
[Seat:*]
autologin-user=${USERNAME}
autologin-user-timeout=0
user-session=cinnamon
EOF

# NetworkManager comme gestionnaire reseau par defaut
cat > "$CHROOT_DIR/etc/NetworkManager/NetworkManager.conf" << EOF
[main]
plugins=ifupdown,keyfile
dns=default

[ifupdown]
managed=true

[device]
wifi.scan-rand-mac-address=no

[connectivity]
uri=http://networkcheck.gnome.org/check_network_status.txt
interval=300
EOF

# Activer NetworkManager
chroot "$CHROOT_DIR" systemctl enable NetworkManager 2>/dev/null || true

# Desactiver les services inutiles pour un live USB
chroot "$CHROOT_DIR" bash -c "
    systemctl disable ssh 2>/dev/null || true
    systemctl disable ModemManager 2>/dev/null || true
" 2>/dev/null || true

# === PHASE 5: INSTALLER CLAUDE CODE ===
log_step "Installation de Claude Code"

chroot "$CHROOT_DIR" bash -c "
    # Installer Claude Code via le script natif
    curl -fsSL https://claude.ai/install.sh | bash 2>/dev/null || {
        echo 'Installation Claude Code via npm fallback...'
        npm install -g @anthropic-ai/claude-code 2>/dev/null || echo 'Claude Code sera installe au premier boot'
    }
"

# === PHASE 6: INSTALLER GITHUB CLI ===
log_step "Installation de GitHub CLI"

chroot "$CHROOT_DIR" bash -c "
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo 'deb [arch=${ARCH} signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main' > /etc/apt/sources.list.d/github-cli.list
    apt-get update
    apt-get install -y gh
"

# === PHASE 7: INSTALLER NETBIRD ===
log_step "Installation de NetBird"

chroot "$CHROOT_DIR" bash -c "
    curl -fsSL https://pkgs.netbird.io/debian/public.key | gpg --dearmor -o /usr/share/keyrings/netbird-archive-keyring.gpg
    echo 'deb [signed-by=/usr/share/keyrings/netbird-archive-keyring.gpg] https://pkgs.netbird.io/debian stable main' > /etc/apt/sources.list.d/netbird.list
    apt-get update
    apt-get install -y netbird 2>/dev/null || echo 'NetBird sera installe au premier boot'
"

# === PHASE 8: INSTALLER VS CODIUM ===
log_step "Installation de VS Codium"

chroot "$CHROOT_DIR" bash -c "
    wget -qO - https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg | gpg --dearmor -o /usr/share/keyrings/vscodium-archive-keyring.gpg
    echo 'deb [signed-by=/usr/share/keyrings/vscodium-archive-keyring.gpg] https://download.vscodium.com/debs vscodium main' > /etc/apt/sources.list.d/vscodium.list
    apt-get update
    apt-get install -y codium 2>/dev/null || echo 'VS Codium sera installe au premier boot'
"

# === PHASE 9: COPIER LES FICHIERS DE CONFIGURATION ===
log_step "Copie des fichiers de configuration EFC"

# Copier les lanceurs desktop
DESKTOP_DIR="$CHROOT_DIR/home/${USERNAME}/Desktop"
mkdir -p "$DESKTOP_DIR"

# Copier tous les .desktop du projet
if [ -d "$SCRIPT_DIR/desktop" ]; then
    cp "$SCRIPT_DIR"/desktop/*.desktop "$DESKTOP_DIR/" 2>/dev/null || true
    chmod +x "$DESKTOP_DIR"/*.desktop 2>/dev/null || true
fi

# Copier les scripts EFC toolkit avec les bons noms
mkdir -p "$CHROOT_DIR/usr/local/bin"
if [ -d "$SCRIPT_DIR/scripts/efc-toolkit" ]; then
    cp "$SCRIPT_DIR/scripts/efc-toolkit/network-tools.sh" "$CHROOT_DIR/usr/local/bin/efc-network-tools"
    cp "$SCRIPT_DIR/scripts/efc-toolkit/ad-tools.sh" "$CHROOT_DIR/usr/local/bin/efc-ad-tools"
    cp "$SCRIPT_DIR/scripts/efc-toolkit/disk-tools.sh" "$CHROOT_DIR/usr/local/bin/efc-disk-tools"
    cp "$SCRIPT_DIR/scripts/efc-toolkit/vpn-tools.sh" "$CHROOT_DIR/usr/local/bin/efc-vpn"
    cp "$SCRIPT_DIR/scripts/efc-toolkit/system-info.sh" "$CHROOT_DIR/usr/local/bin/efc-system-info"
    cp "$SCRIPT_DIR/scripts/efc-toolkit/efc-toolkit.sh" "$CHROOT_DIR/usr/local/bin/efc-toolkit"
    chmod +x "$CHROOT_DIR/usr/local/bin/efc-"*
fi

# Copier le first-boot wizard
if [ -f "$SCRIPT_DIR/scripts/first-boot.sh" ]; then
    cp "$SCRIPT_DIR/scripts/first-boot.sh" "$CHROOT_DIR/usr/local/bin/efc-first-boot"
    chmod +x "$CHROOT_DIR/usr/local/bin/efc-first-boot"

    # Autostart first-boot wizard
    mkdir -p "$CHROOT_DIR/home/${USERNAME}/.config/autostart"
    cat > "$CHROOT_DIR/home/${USERNAME}/.config/autostart/efc-first-boot.desktop" << EOF
[Desktop Entry]
Type=Application
Name=EFC First Boot Wizard
Exec=/usr/local/bin/efc-first-boot
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Comment=Configuration initiale USB-Claude
EOF
fi

# Copier le wallpaper
if [ -f "$SCRIPT_DIR/branding/wallpaper.png" ]; then
    mkdir -p "$CHROOT_DIR/usr/share/backgrounds/efc"
    cp "$SCRIPT_DIR/branding/wallpaper.png" "$CHROOT_DIR/usr/share/backgrounds/efc/"
fi

# Creer le repertoire projets
mkdir -p "$CHROOT_DIR/home/${USERNAME}/projets"

# Configurer Git par defaut
cat > "$CHROOT_DIR/home/${USERNAME}/.gitconfig" << EOF
[user]
    name = Erick Fortin
    email = erick@efcinfo.com
[init]
    defaultBranch = main
[core]
    editor = nano
[pull]
    rebase = false
[color]
    ui = auto
EOF

# Fixer les permissions
chroot "$CHROOT_DIR" chown -R 1000:1000 "/home/${USERNAME}"

# === PHASE 10: NETTOYAGE DU CHROOT ===
log_step "Nettoyage du chroot"

chroot "$CHROOT_DIR" bash -c "
    apt-get clean
    apt-get autoclean
    rm -rf /var/cache/apt/archives/*.deb
    rm -rf /var/lib/apt/lists/*
    rm -rf /tmp/*
    rm -f /var/log/*.log
    rm -f /var/log/apt/*
    > /etc/machine-id
"

# === PHASE 11: CREER LE SQUASHFS ===
log_step "Creation du filesystem squashfs"

# Demonter avant de compresser
cleanup_chroot

SQUASHFS_FILE="/projets/usb-claude-filesystem.squashfs"
rm -f "$SQUASHFS_FILE"

log_info "Compression du systeme (cela prend plusieurs minutes)..."
mksquashfs "$CHROOT_DIR" "$SQUASHFS_FILE" \
    -comp xz \
    -Xbcj x86 \
    -b 1M \
    -no-duplicates \
    -e boot/vmlinuz* boot/initrd* \
    2>&1 | tail -5

SQUASHFS_SIZE=$(du -sh "$SQUASHFS_FILE" | cut -f1)
log_info "Squashfs cree: $SQUASHFS_SIZE"

# === PHASE 12: ASSEMBLER L'ISO ===
log_step "Assemblage de l'ISO bootable"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"/{live,boot/grub,EFI/BOOT,isolinux}

# Copier le kernel et l'initrd
VMLINUZ=$(ls "$CHROOT_DIR"/boot/vmlinuz-* 2>/dev/null | sort -V | tail -1)
INITRD=$(ls "$CHROOT_DIR"/boot/initrd.img-* 2>/dev/null | sort -V | tail -1)

if [ -z "$VMLINUZ" ] || [ -z "$INITRD" ]; then
    log_error "Kernel ou initrd manquant dans le chroot!"
    exit 1
fi

cp "$VMLINUZ" "$BUILD_DIR/live/vmlinuz"
cp "$INITRD" "$BUILD_DIR/live/initrd.img"
cp "$SQUASHFS_FILE" "$BUILD_DIR/live/filesystem.squashfs"

# Config GRUB (UEFI)
cat > "$BUILD_DIR/boot/grub/grub.cfg" << 'EOF'
set default=0
set timeout=5

menuentry "USB-Claude - EFC Informatique" {
    linux /live/vmlinuz boot=live components persistence persistence-media=removable-usb quiet splash
    initrd /live/initrd.img
}

menuentry "USB-Claude - Mode Sans Persistance" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd.img
}

menuentry "USB-Claude - Mode Texte (Recovery)" {
    linux /live/vmlinuz boot=live components persistence persistence-media=removable-usb systemd.unit=multi-user.target
    initrd /live/initrd.img
}

menuentry "USB-Claude - Mode RAM (Copie en RAM)" {
    linux /live/vmlinuz boot=live components toram quiet splash
    initrd /live/initrd.img
}
EOF

# Creer l'image EFI
EFI_IMG="$BUILD_DIR/boot/grub/efi.img"
dd if=/dev/zero of="$EFI_IMG" bs=1M count=10
mkfs.fat -F 12 "$EFI_IMG"
EFI_MNT=$(mktemp -d)
mount "$EFI_IMG" "$EFI_MNT"
mkdir -p "$EFI_MNT/EFI/BOOT"

# Generer le bootloader EFI
grub-mkimage \
    -o "$EFI_MNT/EFI/BOOT/BOOTx64.EFI" \
    -p /boot/grub \
    -O x86_64-efi \
    fat iso9660 part_gpt part_msdos normal boot linux configfile loopback chain efifwsetup \
    efi_gop efi_uga ls search search_label search_fs_uuid search_fs_file gfxterm gfxterm_background \
    gfxterm_menu test all_video loadenv exfat ext2 ntfs btrfs hfsplus udf

cp "$EFI_MNT/EFI/BOOT/BOOTx64.EFI" "$BUILD_DIR/EFI/BOOT/"
umount "$EFI_MNT"
rmdir "$EFI_MNT"

# Config isolinux (Legacy BIOS)
if [ -f /usr/lib/ISOLINUX/isolinux.bin ]; then
    cp /usr/lib/ISOLINUX/isolinux.bin "$BUILD_DIR/isolinux/"
    cp /usr/lib/syslinux/modules/bios/{ldlinux.c32,libcom32.c32,libutil.c32,vesamenu.c32} "$BUILD_DIR/isolinux/" 2>/dev/null || true

    cat > "$BUILD_DIR/isolinux/isolinux.cfg" << 'EOF'
DEFAULT usb-claude
TIMEOUT 50
PROMPT 0

LABEL usb-claude
    MENU LABEL USB-Claude - EFC Informatique
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live components persistence persistence-media=removable-usb quiet splash

LABEL nopersist
    MENU LABEL USB-Claude - Sans Persistance
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live components quiet splash

LABEL recovery
    MENU LABEL USB-Claude - Mode Texte (Recovery)
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live components persistence persistence-media=removable-usb systemd.unit=multi-user.target
EOF
else
    log_warn "isolinux.bin non trouve - Legacy BIOS boot non disponible"
    log_warn "Installer: apt install isolinux syslinux-common"
fi

# Generer l'ISO
log_info "Generation de l'ISO finale..."
xorriso -as mkisofs \
    -o "$ISO_OUTPUT" \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -V "USB-CLAUDE" \
    "$BUILD_DIR" 2>&1 | tail -5

if [ -f "$ISO_OUTPUT" ]; then
    ISO_SIZE=$(du -sh "$ISO_OUTPUT" | cut -f1)
    log_info ""
    log_info "============================================"
    log_info "  BUILD TERMINE AVEC SUCCES!"
    log_info "============================================"
    log_info "  ISO: $ISO_OUTPUT"
    log_info "  Taille: $ISO_SIZE"
    log_info "  Version: $VERSION"
    log_info ""
    log_info "  Pour ecrire sur la cle USB:"
    log_info "  sudo ./write-to-usb.sh /dev/sdX"
    log_info "============================================"
else
    log_error "Echec de la generation de l'ISO!"
    exit 1
fi
