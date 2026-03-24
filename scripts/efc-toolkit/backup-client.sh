#!/bin/bash
# =============================================================================
# EFC Client Backup - Backup donnees client avec Midnight Commander
# Liste les disques/partitions, monte la source, ouvre MC pour copier
# =============================================================================

BACKUP_DIR="$HOME/projets/backups"

echo "============================================"
echo "  EFC Informatique - Backup Client"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

# Lister les disques et partitions
echo "=== Disques et partitions detectes ==="
echo ""
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MODEL,MOUNTPOINTS | grep -v loop
echo ""

# Demander quelle partition monter
echo "Quelle partition veux-tu sauvegarder?"
echo "(ex: sda1, sda2, nvme0n1p1, etc.)"
echo ""
read -p "Partition: /dev/" PART

if [ -z "$PART" ]; then
    echo "Annule."
    exit 0
fi

DEVICE="/dev/$PART"

if [ ! -b "$DEVICE" ]; then
    echo "ERREUR: $DEVICE n'existe pas"
    exit 1
fi

# Detecter le filesystem
FSTYPE=$(blkid -o value -s TYPE "$DEVICE" 2>/dev/null)
echo ""
echo "Partition: $DEVICE"
echo "Filesystem: ${FSTYPE:-inconnu}"

# Point de montage
MOUNT_SRC="/mnt/client-source"
sudo mkdir -p "$MOUNT_SRC"

# Monter selon le type
case "$FSTYPE" in
    ntfs)
        echo "Montage NTFS (lecture seule pour securite)..."
        sudo mount -t ntfs-3g -o ro "$DEVICE" "$MOUNT_SRC"
        ;;
    ext4|ext3|ext2|btrfs|xfs)
        echo "Montage $FSTYPE (lecture seule)..."
        sudo mount -o ro "$DEVICE" "$MOUNT_SRC"
        ;;
    vfat|exfat)
        echo "Montage $FSTYPE..."
        sudo mount -o ro "$DEVICE" "$MOUNT_SRC"
        ;;
    "")
        echo "Filesystem non detecte. Tentative de montage auto..."
        sudo mount -o ro "$DEVICE" "$MOUNT_SRC" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "ERREUR: Impossible de monter $DEVICE"
            echo "La partition est peut-etre chiffree ou corrompue."
            exit 1
        fi
        ;;
    *)
        echo "Montage $FSTYPE..."
        sudo mount -o ro "$DEVICE" "$MOUNT_SRC"
        ;;
esac

if ! mountpoint -q "$MOUNT_SRC"; then
    echo "ERREUR: Echec du montage de $DEVICE"
    exit 1
fi

echo "Monte sur $MOUNT_SRC"
echo ""

# Creer le dossier backup avec date et nom client
read -p "Nom du client (ex: cao, dupont): " CLIENT_NAME
CLIENT_NAME=${CLIENT_NAME:-client}
BACKUP_DEST="$BACKUP_DIR/${CLIENT_NAME}_$(date '+%Y%m%d_%H%M')"
mkdir -p "$BACKUP_DEST"

echo ""
echo "============================================"
echo "  Midnight Commander va s'ouvrir"
echo ""
echo "  GAUCHE:  Source client ($MOUNT_SRC)"
echo "  DROITE:  Backup ($BACKUP_DEST)"
echo ""
echo "  Utilise F5 pour copier les fichiers"
echo "  Utilise F10 pour quitter MC"
echo "============================================"
echo ""
read -p "Appuyer sur Entree pour ouvrir MC..."

# Ouvrir MC avec source a gauche et backup a droite
mc "$MOUNT_SRC" "$BACKUP_DEST"

# Apres fermeture de MC
echo ""
echo "=== Backup termine ==="
BACKUP_SIZE=$(du -sh "$BACKUP_DEST" 2>/dev/null | cut -f1)
echo "Dossier: $BACKUP_DEST"
echo "Taille:  $BACKUP_SIZE"
echo ""

# Demonter la partition client
sudo umount "$MOUNT_SRC" 2>/dev/null
echo "Partition client demontee."
echo ""
read -p "Appuyer sur Entree pour continuer..."
