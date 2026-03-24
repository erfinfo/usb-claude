#!/bin/bash
# =============================================================================
# EFC Disk Repair Wizard - Diagnostic et reparation de disques
# Guide le technicien a travers le diagnostic et la reparation
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "  ${YELLOW}[!!]${NC} $1"; }
log_fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }
log_info() { echo -e "  ${CYAN}[i]${NC} $1"; }

# === SELECTION DU DISQUE ===
select_disk() {
    echo ""
    echo -e "${CYAN}=== Disques detectes ===${NC}"
    echo ""

    # Lister les disques physiques (pas les partitions, pas les loop)
    DISKS=()
    INDEX=1
    while IFS= read -r line; do
        NAME=$(echo "$line" | awk '{print $1}')
        SIZE=$(echo "$line" | awk '{print $2}')
        MODEL=$(echo "$line" | awk '{$1=$2=$3=$4=""; print $0}' | xargs)
        echo "  $INDEX) /dev/$NAME  [$SIZE]  $MODEL"
        DISKS+=("$NAME")
        ((INDEX++))
    done < <(lsblk -d -n -o NAME,SIZE,TYPE,TRAN,MODEL | grep -E "disk" | grep -v loop)

    echo ""
    read -p "  Selectionner un disque (1-${#DISKS[@]}): " CHOICE

    if [ -z "$CHOICE" ] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "${#DISKS[@]}" ] 2>/dev/null; then
        echo "Selection invalide."
        return 1
    fi

    SELECTED_DISK="/dev/${DISKS[$((CHOICE-1))]}"
    echo ""
    echo -e "${CYAN}  Disque selectionne: $SELECTED_DISK${NC}"
    return 0
}

# === DIAGNOSTIC COMPLET ===
run_diagnostic() {
    local DISK="$1"

    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  DIAGNOSTIC: $DISK${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""

    # 1. Info disque
    echo -e "${CYAN}--- Info disque ---${NC}"
    MODEL=$(lsblk -d -n -o MODEL "$DISK" 2>/dev/null | xargs)
    SIZE=$(lsblk -d -n -o SIZE "$DISK" 2>/dev/null | xargs)
    TRAN=$(lsblk -d -n -o TRAN "$DISK" 2>/dev/null | xargs)
    log_info "Modele: $MODEL"
    log_info "Taille: $SIZE"
    log_info "Interface: $TRAN"
    echo ""

    # 2. Table de partitions
    echo -e "${CYAN}--- Table de partitions ---${NC}"
    PART_TABLE=$(sudo fdisk -l "$DISK" 2>&1)
    if echo "$PART_TABLE" | grep -q "doesn't contain a valid partition table\|ne contient pas une table de partitions valide"; then
        log_fail "AUCUNE table de partitions valide!"
        PART_STATUS="MISSING"
    elif echo "$PART_TABLE" | grep -q "GPT"; then
        log_ok "Table GPT detectee"
        PART_STATUS="GPT"
    elif echo "$PART_TABLE" | grep -q "DOS\|MBR"; then
        log_ok "Table MBR/DOS detectee"
        PART_STATUS="MBR"
    else
        log_warn "Type de table inconnu"
        PART_STATUS="UNKNOWN"
    fi

    # Lister les partitions
    echo ""
    PARTITIONS=$(lsblk -n -o NAME,SIZE,FSTYPE,LABEL "$DISK" | grep -v "^$(basename $DISK) ")
    if [ -z "$PARTITIONS" ]; then
        log_fail "Aucune partition trouvee"
    else
        echo "  Partitions:"
        echo "$PARTITIONS" | while read -r line; do
            echo "    $line"
        done
    fi
    echo ""

    # 3. SMART
    echo -e "${CYAN}--- Sante SMART ---${NC}"
    SMART=$(sudo smartctl -H "$DISK" 2>&1)
    if echo "$SMART" | grep -qi "PASSED"; then
        log_ok "SMART: PASSED (disque en sante)"
        SMART_STATUS="OK"
    elif echo "$SMART" | grep -qi "FAILED"; then
        log_fail "SMART: FAILED - DISQUE DEFAILLANT!"
        SMART_STATUS="FAILED"
    else
        log_warn "SMART non supporte ou non disponible"
        SMART_STATUS="UNKNOWN"
    fi

    # Temperature
    TEMP=$(sudo smartctl -A "$DISK" 2>/dev/null | grep -i "temperature" | head -1 | awk '{print $NF}')
    [ -n "$TEMP" ] && log_info "Temperature: ${TEMP}C"

    # Heures d'utilisation
    HOURS=$(sudo smartctl -A "$DISK" 2>/dev/null | grep -i "power_on_hours\|Power On Hours" | awk '{print $NF}')
    [ -n "$HOURS" ] && log_info "Heures d'utilisation: $HOURS h"

    # Secteurs realloues
    REALLOC=$(sudo smartctl -A "$DISK" 2>/dev/null | grep -i "reallocated" | awk '{print $NF}')
    if [ -n "$REALLOC" ] && [ "$REALLOC" -gt 0 ] 2>/dev/null; then
        log_warn "Secteurs realloues: $REALLOC (signe d'usure)"
    fi
    echo ""

    # 4. Verifier chaque partition
    echo -e "${CYAN}--- Verification des filesystems ---${NC}"
    for part in "${DISK}"*; do
        [ "$part" = "$DISK" ] && continue
        [ ! -b "$part" ] && continue

        FSTYPE=$(blkid -o value -s TYPE "$part" 2>/dev/null)
        LABEL=$(blkid -o value -s LABEL "$part" 2>/dev/null)

        case "$FSTYPE" in
            ntfs)
                NTFS_CHECK=$(sudo ntfsfix -n "$part" 2>&1)
                if echo "$NTFS_CHECK" | grep -qi "dirty\|error\|inconsistent"; then
                    log_warn "$part ($FSTYPE ${LABEL:+[$LABEL]}) - ERREURS DETECTEES"
                else
                    log_ok "$part ($FSTYPE ${LABEL:+[$LABEL]}) - OK"
                fi
                ;;
            ext4|ext3|ext2)
                EXT_CHECK=$(sudo e2fsck -n "$part" 2>&1)
                if echo "$EXT_CHECK" | grep -qi "clean"; then
                    log_ok "$part ($FSTYPE ${LABEL:+[$LABEL]}) - Clean"
                else
                    log_warn "$part ($FSTYPE ${LABEL:+[$LABEL]}) - Necesssite reparation"
                fi
                ;;
            vfat|exfat)
                log_ok "$part ($FSTYPE ${LABEL:+[$LABEL]}) - (non verifiable en ligne)"
                ;;
            "")
                log_warn "$part - Filesystem non reconnu"
                ;;
            *)
                log_info "$part ($FSTYPE ${LABEL:+[$LABEL]})"
                ;;
        esac
    done
    echo ""

    # 5. Resume et recommandations
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  RESUME DIAGNOSTIC${NC}"
    echo -e "${CYAN}============================================${NC}"

    if [ "$SMART_STATUS" = "FAILED" ]; then
        log_fail "DISQUE DEFAILLANT - Sauvegarder les donnees IMMEDIATEMENT"
        log_info "Recommandation: ddrescue pour cloner, puis recuperer les fichiers"
    elif [ "$PART_STATUS" = "MISSING" ]; then
        log_fail "Table de partitions manquante ou corrompue"
        log_info "Recommandation: TestDisk pour recuperer la table de partitions"
    fi
    echo ""
}

# === MENU REPARATION ===
repair_menu() {
    local DISK="$1"

    while true; do
        CHOICE=$(whiptail --title "EFC Disk Repair - $DISK" --menu \
            "Que veux-tu reparer?" 22 70 12 \
            "1" "Reparer le filesystem (fsck/ntfsfix)" \
            "2" "Recuperer la table de partitions (TestDisk)" \
            "3" "Recuperer des fichiers supprimes (PhotoRec)" \
            "4" "Reparer le boot Windows (chntpw/bootrec)" \
            "5" "Reparer le boot Linux (GRUB)" \
            "6" "Cloner le disque (ddrescue - disque defaillant)" \
            "7" "Reset mot de passe Windows" \
            "8" "Voir le rapport SMART complet" \
            "9" "Ouvrir GParted (editeur partitions)" \
            "D" "Relancer le diagnostic" \
            "Q" "Quitter" \
            3>&1 1>&2 2>&3)

        case "$CHOICE" in
            1) repair_filesystem "$DISK" ;;
            2) recover_partition_table "$DISK" ;;
            3) recover_files "$DISK" ;;
            4) repair_windows_boot "$DISK" ;;
            5) repair_linux_boot "$DISK" ;;
            6) clone_disk "$DISK" ;;
            7) reset_windows_password "$DISK" ;;
            8) sudo smartctl -a "$DISK" | less ;;
            9) sudo gparted "$DISK" & ;;
            D|d) run_diagnostic "$DISK" ; read -p "Appuyer sur Entree..." ;;
            Q|q|"") return ;;
        esac
    done
}

# === REPARATION FILESYSTEM ===
repair_filesystem() {
    local DISK="$1"
    echo ""
    echo "=== Partitions sur $DISK ==="
    lsblk -n -o NAME,SIZE,FSTYPE,LABEL "$DISK" | grep -v "^$(basename $DISK) "
    echo ""
    read -p "Partition a reparer (ex: sda1): /dev/" PART
    [ -z "$PART" ] && return

    DEVICE="/dev/$PART"
    FSTYPE=$(blkid -o value -s TYPE "$DEVICE" 2>/dev/null)

    echo ""
    echo "Partition: $DEVICE"
    echo "Filesystem: $FSTYPE"
    echo ""

    case "$FSTYPE" in
        ntfs)
            echo "=== Reparation NTFS ==="
            echo "Etape 1: ntfsfix (reparation rapide)..."
            sudo ntfsfix "$DEVICE"
            echo ""
            echo "Si ca ne suffit pas, il faudra booter Windows et faire:"
            echo "  chkdsk /f C:"
            ;;
        ext4|ext3|ext2)
            echo "=== Reparation $FSTYPE ==="
            echo "ATTENTION: la partition ne doit PAS etre montee!"
            sudo umount "$DEVICE" 2>/dev/null
            echo ""
            sudo e2fsck -f -y "$DEVICE"
            ;;
        vfat)
            echo "=== Reparation FAT ==="
            sudo fsck.fat -a "$DEVICE"
            ;;
        exfat)
            echo "=== Reparation exFAT ==="
            sudo exfatfsck "$DEVICE"
            ;;
        btrfs)
            echo "=== Verification Btrfs ==="
            sudo btrfs check "$DEVICE"
            ;;
        *)
            echo "Filesystem $FSTYPE non supporte pour la reparation automatique."
            echo "Essayez TestDisk pour recuperer les donnees."
            ;;
    esac
    echo ""
    read -p "Appuyer sur Entree..."
}

# === RECUPERER TABLE DE PARTITIONS ===
recover_partition_table() {
    local DISK="$1"
    echo ""
    echo "=== TestDisk - Recuperation de la table de partitions ==="
    echo ""
    echo "TestDisk va scanner $DISK pour retrouver les partitions perdues."
    echo "Suivez les instructions a l'ecran:"
    echo "  1. Selectionner le disque"
    echo "  2. Selectionner le type de table (Intel/GPT)"
    echo "  3. Analyse > Quick Search"
    echo "  4. Si partitions trouvees > Write pour restaurer"
    echo ""
    read -p "Appuyer sur Entree pour lancer TestDisk..."
    sudo testdisk "$DISK"
}

# === RECUPERER FICHIERS ===
recover_files() {
    local DISK="$1"
    RECOVER_DIR="$HOME/projets/backups/recovery_$(date '+%Y%m%d_%H%M')"
    mkdir -p "$RECOVER_DIR"

    echo ""
    echo "=== PhotoRec - Recuperation de fichiers ==="
    echo ""
    echo "Les fichiers recuperes seront sauvegardes dans:"
    echo "  $RECOVER_DIR"
    echo ""
    echo "Dans PhotoRec:"
    echo "  1. Selectionner la partition"
    echo "  2. Choisir le filesystem (ext4/NTFS/FAT)"
    echo "  3. Choisir 'Free' (espace libre) ou 'Whole' (tout)"
    echo "  4. Selectionner le dossier de destination"
    echo ""
    read -p "Appuyer sur Entree pour lancer PhotoRec..."
    sudo photorec /d "$RECOVER_DIR" "$DISK"

    echo ""
    RECOVERED=$(find "$RECOVER_DIR" -type f | wc -l)
    SIZE=$(du -sh "$RECOVER_DIR" 2>/dev/null | cut -f1)
    echo "Fichiers recuperes: $RECOVERED ($SIZE)"
    read -p "Appuyer sur Entree..."
}

# === REPARER BOOT WINDOWS ===
repair_windows_boot() {
    local DISK="$1"
    echo ""
    echo "=== Reparation Boot Windows ==="
    echo ""

    # Trouver la partition Windows
    WIN_PART=""
    for part in "${DISK}"*; do
        [ "$part" = "$DISK" ] && continue
        FSTYPE=$(blkid -o value -s TYPE "$part" 2>/dev/null)
        if [ "$FSTYPE" = "ntfs" ]; then
            MOUNT_TMP=$(mktemp -d)
            sudo mount -t ntfs-3g -o ro "$part" "$MOUNT_TMP" 2>/dev/null
            if [ -d "$MOUNT_TMP/Windows/System32" ]; then
                WIN_PART="$part"
                sudo umount "$MOUNT_TMP"
                rmdir "$MOUNT_TMP"
                break
            fi
            sudo umount "$MOUNT_TMP" 2>/dev/null
            rmdir "$MOUNT_TMP"
        fi
    done

    if [ -z "$WIN_PART" ]; then
        echo "Aucune partition Windows trouvee sur $DISK"
        echo ""
        echo "Options:"
        echo "  1. Verifier si le disque est le bon"
        echo "  2. Utiliser TestDisk pour recuperer la table de partitions"
        echo "  3. La partition Windows est peut-etre corrompue"
    else
        echo "Windows trouve sur: $WIN_PART"
        echo ""
        echo "Options de reparation du boot Windows:"
        echo ""
        echo "  1. Reparer le BCD (UEFI):"
        echo "     - Booter sur un USB d'installation Windows"
        echo "     - Repair your computer > Troubleshoot > Command Prompt"
        echo "     - bootrec /fixmbr"
        echo "     - bootrec /fixboot"
        echo "     - bootrec /rebuildbcd"
        echo ""
        echo "  2. Reparer NTFS (depuis ici):"
        echo "     sudo ntfsfix $WIN_PART"
        echo ""

        read -p "Lancer ntfsfix maintenant? (o/n): " FIX
        if [ "$FIX" = "o" ]; then
            sudo ntfsfix "$WIN_PART"
        fi
    fi
    echo ""
    read -p "Appuyer sur Entree..."
}

# === REPARER BOOT LINUX ===
repair_linux_boot() {
    local DISK="$1"
    echo ""
    echo "=== Reparation Boot Linux (GRUB) ==="
    echo ""

    # Trouver la partition Linux root
    LINUX_PART=""
    for part in "${DISK}"*; do
        [ "$part" = "$DISK" ] && continue
        FSTYPE=$(blkid -o value -s TYPE "$part" 2>/dev/null)
        if [ "$FSTYPE" = "ext4" ]; then
            MOUNT_TMP=$(mktemp -d)
            sudo mount "$part" "$MOUNT_TMP" 2>/dev/null
            if [ -d "$MOUNT_TMP/boot" ] && [ -d "$MOUNT_TMP/etc" ]; then
                LINUX_PART="$part"
                LINUX_MNT="$MOUNT_TMP"
                break
            fi
            sudo umount "$MOUNT_TMP" 2>/dev/null
            rmdir "$MOUNT_TMP"
        fi
    done

    if [ -z "$LINUX_PART" ]; then
        echo "Aucune partition Linux trouvee sur $DISK"
    else
        echo "Linux trouve sur: $LINUX_PART (monte sur $LINUX_MNT)"
        echo ""
        echo "Reinstallation de GRUB..."

        # Bind mount
        sudo mount --bind /dev "$LINUX_MNT/dev"
        sudo mount --bind /proc "$LINUX_MNT/proc"
        sudo mount --bind /sys "$LINUX_MNT/sys"

        # Reinstaller GRUB
        sudo chroot "$LINUX_MNT" grub-install "$DISK" 2>&1
        sudo chroot "$LINUX_MNT" update-grub 2>&1

        # Nettoyer
        sudo umount "$LINUX_MNT/dev" "$LINUX_MNT/proc" "$LINUX_MNT/sys"
        sudo umount "$LINUX_MNT"
        rmdir "$LINUX_MNT" 2>/dev/null

        echo ""
        echo "GRUB reinstalle sur $DISK"
    fi
    echo ""
    read -p "Appuyer sur Entree..."
}

# === CLONER DISQUE ===
clone_disk() {
    local DISK="$1"
    echo ""
    echo "=== DDRescue - Clone de disque defaillant ==="
    echo ""
    echo "IMPORTANT: DDRescue est concu pour les disques defaillants."
    echo "Il copie d'abord les secteurs lisibles, puis retente les erreurs."
    echo ""

    echo "Disques disponibles pour la destination:"
    lsblk -d -o NAME,SIZE,MODEL | grep -v loop | grep -v "$(basename $DISK)"
    echo ""

    read -p "Sauvegarder vers un fichier image? (o/n): " IMG_MODE

    if [ "$IMG_MODE" = "o" ]; then
        DEST="$HOME/projets/backups/disk_$(basename $DISK)_$(date '+%Y%m%d').img"
        LOG="${DEST}.log"
        echo "Destination: $DEST"
        echo "Log: $LOG"
    else
        read -p "Disque destination (ex: sdb): /dev/" DEST_DISK
        DEST="/dev/$DEST_DISK"
        LOG="$HOME/projets/backups/ddrescue_$(date '+%Y%m%d').log"

        echo ""
        echo -e "${RED}ATTENTION: Toutes les donnees sur $DEST seront ecrasees!${NC}"
        read -p "Continuer? (tapez OUI): " CONFIRM
        [ "$CONFIRM" != "OUI" ] && return
    fi

    echo ""
    echo "Lancement de ddrescue (Ctrl+C pour pause, reprend automatiquement)..."
    echo ""
    sudo ddrescue -f -n "$DISK" "$DEST" "$LOG"

    echo ""
    echo "Clone termine. Verifier le log: $LOG"
    read -p "Appuyer sur Entree..."
}

# === RESET MOT DE PASSE WINDOWS ===
reset_windows_password() {
    local DISK="$1"
    echo ""
    echo "=== Reset Mot de Passe Windows ==="
    echo ""

    # Trouver la partition Windows
    for part in "${DISK}"*; do
        [ "$part" = "$DISK" ] && continue
        FSTYPE=$(blkid -o value -s TYPE "$part" 2>/dev/null)
        [ "$FSTYPE" != "ntfs" ] && continue

        MOUNT_TMP=$(mktemp -d)
        sudo mount -t ntfs-3g "$part" "$MOUNT_TMP" 2>/dev/null

        SAM="$MOUNT_TMP/Windows/System32/config/SAM"
        if [ -f "$SAM" ]; then
            echo "Windows trouve sur $part"
            echo ""
            echo "=== Utilisateurs Windows ==="
            sudo chntpw -l "$SAM"
            echo ""
            read -p "Utilisateur a reset (ex: Administrator, admin): " USERNAME
            if [ -n "$USERNAME" ]; then
                echo ""
                echo "Options:"
                echo "  1 - Effacer le mot de passe (recommande)"
                echo "  2 - Promouvoir en admin"
                echo "  3 - Deverrouiller le compte"
                echo ""
                sudo chntpw -u "$USERNAME" "$SAM"
            fi
            sudo umount "$MOUNT_TMP"
            rmdir "$MOUNT_TMP"
            read -p "Appuyer sur Entree..."
            return
        fi
        sudo umount "$MOUNT_TMP" 2>/dev/null
        rmdir "$MOUNT_TMP"
    done

    echo "Aucune partition Windows avec SAM trouvee sur $DISK"
    read -p "Appuyer sur Entree..."
}

# === MAIN ===
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  EFC Disk Repair Wizard${NC}"
echo -e "${CYAN}  EFC Informatique - erick@efcinfo.com${NC}"
echo -e "${CYAN}============================================${NC}"

if ! select_disk; then
    exit 1
fi

echo ""
echo "Lancement du diagnostic..."
run_diagnostic "$SELECTED_DISK"

read -p "Appuyer sur Entree pour acceder au menu de reparation..."
repair_menu "$SELECTED_DISK"
