#!/bin/bash
# =============================================================================
# USB-Claude - Ecriture sur cle USB
# Cree les partitions, installe GRUB, et configure la persistance
#
# Usage: sudo ./write-to-usb.sh /dev/sdX
# =============================================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERREUR]${NC} $1"; }
log_step()  { echo -e "\n${CYAN}=== $1 ===${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ISO_FILE="$(ls -t "$SCRIPT_DIR"/usb-claude-*.iso 2>/dev/null | head -1)"

# === VERIFICATIONS ===
if [ "$(id -u)" -ne 0 ]; then
    log_error "Ce script doit etre execute en root (sudo)"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: sudo $0 /dev/sdX"
    echo ""
    echo "Peripheriques USB detectes:"
    lsblk -d -o NAME,SIZE,MODEL,TRAN,HOTPLUG | grep -E "usb|^NAME"
    exit 1
fi

TARGET="$1"

if [ ! -b "$TARGET" ]; then
    log_error "$TARGET n'est pas un peripherique bloc valide"
    exit 1
fi

# Verifier que c'est bien un USB
if [ "$(cat /sys/block/$(basename $TARGET)/removable 2>/dev/null)" != "1" ]; then
    log_error "$TARGET ne semble pas etre un peripherique amovible (USB)"
    log_error "Verification de securite: on n'ecrit PAS sur un disque interne"
    exit 1
fi

if [ -z "$ISO_FILE" ] || [ ! -f "$ISO_FILE" ]; then
    log_error "Aucune ISO USB-Claude trouvee dans $SCRIPT_DIR"
    log_error "Executez d'abord: sudo ./build-usb-claude.sh"
    exit 1
fi

TARGET_SIZE=$(lsblk -b -d -o SIZE "$TARGET" | tail -1 | tr -d ' ')
TARGET_SIZE_GB=$((TARGET_SIZE / 1024 / 1024 / 1024))
TARGET_MODEL=$(lsblk -d -o MODEL "$TARGET" | tail -1 | xargs)

echo ""
echo -e "${YELLOW}============================================${NC}"
echo -e "${YELLOW}  ATTENTION - ECRITURE SUR CLE USB${NC}"
echo -e "${YELLOW}============================================${NC}"
echo ""
echo "  Cible:   $TARGET"
echo "  Modele:  $TARGET_MODEL"
echo "  Taille:  ${TARGET_SIZE_GB} GB"
echo "  ISO:     $(basename $ISO_FILE)"
echo ""
echo -e "${RED}  TOUTES LES DONNEES SERONT EFFACEES!${NC}"
echo ""
read -p "Continuer? (tapez OUI en majuscules): " CONFIRM

if [ "$CONFIRM" != "OUI" ]; then
    log_info "Annule."
    exit 0
fi

# === DEMONTAGE ===
log_step "Demontage des partitions existantes"
for part in "${TARGET}"*; do
    umount "$part" 2>/dev/null || true
done

# === PARTITIONNEMENT ===
log_step "Partitionnement de $TARGET"

# Effacer la table de partition
wipefs -a "$TARGET" 2>/dev/null || true
sgdisk --zap-all "$TARGET" 2>/dev/null || true

# Creer une table GPT avec 3 partitions
parted -s "$TARGET" mklabel gpt

# Partition 1: EFI System Partition (512 MB)
parted -s "$TARGET" mkpart "EFI" fat32 1MiB 513MiB
parted -s "$TARGET" set 1 esp on

# Partition 2: Live System (10 GB - assez pour l'ISO expandue)
parted -s "$TARGET" mkpart "LIVE" ext4 513MiB 10753MiB

# Partition 3: Persistence (tout le reste)
parted -s "$TARGET" mkpart "persistence" ext4 10753MiB 100%

# Attendre que les partitions soient detectees
sleep 2
partprobe "$TARGET" 2>/dev/null || true
sleep 2

# Determiner les noms de partitions
if [ -b "${TARGET}1" ]; then
    PART_EFI="${TARGET}1"
    PART_LIVE="${TARGET}2"
    PART_PERSIST="${TARGET}3"
elif [ -b "${TARGET}p1" ]; then
    PART_EFI="${TARGET}p1"
    PART_LIVE="${TARGET}p2"
    PART_PERSIST="${TARGET}p3"
else
    log_error "Impossible de trouver les partitions creees"
    exit 1
fi

# === FORMATAGE ===
log_step "Formatage des partitions"

log_info "Formatage EFI (FAT32)..."
mkfs.fat -F 32 -n "EFI" "$PART_EFI"

log_info "Formatage Live (ext4)..."
mkfs.ext4 -L "USB-CLAUDE" -F "$PART_LIVE"

log_info "Formatage Persistence (ext4)..."
mkfs.ext4 -L "persistence" -F "$PART_PERSIST"

# === COPIE DU SYSTEME LIVE ===
log_step "Copie du systeme live"

LIVE_MNT=$(mktemp -d)
mount "$PART_LIVE" "$LIVE_MNT"

# Extraire l'ISO
ISO_MNT=$(mktemp -d)
mount -o loop "$ISO_FILE" "$ISO_MNT"
cp -a "$ISO_MNT"/* "$LIVE_MNT/"
umount "$ISO_MNT"
rmdir "$ISO_MNT"

log_info "Systeme live copie"

# === INSTALLATION DE GRUB ===
log_step "Installation de GRUB (UEFI + Legacy)"

# GRUB UEFI
EFI_MNT=$(mktemp -d)
mount "$PART_EFI" "$EFI_MNT"
mkdir -p "$EFI_MNT/EFI/BOOT"

if [ -d "$LIVE_MNT/EFI/BOOT" ]; then
    cp "$LIVE_MNT/EFI/BOOT/BOOTx64.EFI" "$EFI_MNT/EFI/BOOT/"
fi

# Copier la config GRUB sur EFI aussi
mkdir -p "$EFI_MNT/boot/grub"
cp "$LIVE_MNT/boot/grub/grub.cfg" "$EFI_MNT/boot/grub/" 2>/dev/null || true

umount "$EFI_MNT"
rmdir "$EFI_MNT"

# GRUB Legacy (MBR) - pour les machines sans UEFI
grub-install --target=i386-pc \
    --boot-directory="$LIVE_MNT/boot" \
    --recheck "$TARGET" 2>/dev/null || log_warn "GRUB Legacy non installe (UEFI seulement)"

umount "$LIVE_MNT"
rmdir "$LIVE_MNT"

# === CONFIGURATION DE LA PERSISTANCE ===
log_step "Configuration de la persistance"

PERSIST_MNT=$(mktemp -d)
mount "$PART_PERSIST" "$PERSIST_MNT"

# persistence.conf - definit ce qui est persistant
cat > "$PERSIST_MNT/persistence.conf" << 'EOF'
/home union
/etc union
/var/lib union
/usr/local union
/root union
EOF

# Creer le repertoire home de base
mkdir -p "$PERSIST_MNT/home/erick/projets"
mkdir -p "$PERSIST_MNT/home/erick/Desktop"
mkdir -p "$PERSIST_MNT/home/erick/.config"
mkdir -p "$PERSIST_MNT/home/erick/.claude"
mkdir -p "$PERSIST_MNT/home/erick/.ssh"

# Copier les lanceurs desktop sur la persistance
if [ -d "$SCRIPT_DIR/desktop" ]; then
    cp "$SCRIPT_DIR"/desktop/*.desktop "$PERSIST_MNT/home/erick/Desktop/" 2>/dev/null || true
    chmod +x "$PERSIST_MNT/home/erick/Desktop/"*.desktop 2>/dev/null || true
fi

# Copier le wallpaper
if [ -f "$SCRIPT_DIR/branding/wallpaper.png" ]; then
    mkdir -p "$PERSIST_MNT/usr/local/share/backgrounds/efc"
    cp "$SCRIPT_DIR/branding/wallpaper.png" "$PERSIST_MNT/usr/local/share/backgrounds/efc/"
fi

# Fixer les permissions (UID 1000 = erick)
chown -R 1000:1000 "$PERSIST_MNT/home/erick"

umount "$PERSIST_MNT"
rmdir "$PERSIST_MNT"

# === VERIFICATION ===
log_step "Verification"

echo ""
echo "Partitions creees:"
lsblk -o NAME,SIZE,TYPE,LABEL,FSTYPE "$TARGET"
echo ""

log_info "============================================"
log_info "  ECRITURE TERMINEE AVEC SUCCES!"
log_info "============================================"
log_info ""
log_info "  Cle USB: $TARGET (${TARGET_SIZE_GB} GB)"
log_info "  EFI:     $PART_EFI (512 MB)"
log_info "  Live:    $PART_LIVE (10 GB)"
log_info "  Persist: $PART_PERSIST (~${TARGET_SIZE_GB-11} GB)"
log_info ""
log_info "  Tu peux maintenant booter sur la cle USB!"
log_info "  F12 au demarrage → Selectionner USB"
log_info "============================================"
