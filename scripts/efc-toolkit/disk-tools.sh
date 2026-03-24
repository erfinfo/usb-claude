#!/bin/bash
# =============================================================================
# EFC Disk Tools - Menu interactif outils disques
# =============================================================================

while true; do
    CHOICE=$(whiptail --title "EFC - Outils Disques & Recovery" --menu "Choisir un outil:" 20 70 10 \
        "1" "GParted (editeur de partitions)" \
        "2" "Lister les disques (lsblk)" \
        "3" "Info SMART disque" \
        "4" "TestDisk (recovery partitions)" \
        "5" "PhotoRec (recovery fichiers)" \
        "6" "DDRescue (clone disque)" \
        "7" "Reset mot de passe Windows (chntpw)" \
        "8" "Monter une partition NTFS" \
        "9" "Benchmark disque (fio)" \
        "Q" "Quitter" \
        3>&1 1>&2 2>&3)

    case "$CHOICE" in
        1)
            sudo gparted &
            ;;
        2)
            echo "=== Disques et partitions ==="
            lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL
            echo ""
            echo "=== Espace utilise ==="
            df -hT | grep -v tmpfs | grep -v loop
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        3)
            echo "=== Disques disponibles ==="
            lsblk -d -o NAME,SIZE,MODEL
            DISK=$(whiptail --inputbox "Disque a verifier (ex: sda):" 8 60 "sda" 3>&1 1>&2 2>&3)
            if [ -n "$DISK" ]; then
                echo "=== Info SMART /dev/$DISK ==="
                sudo smartctl -a "/dev/$DISK"
            fi
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        4)
            echo "=== TestDisk - Recovery de partitions ==="
            echo "Selectionner le disque dans l'interface..."
            sudo testdisk
            ;;
        5)
            echo "=== PhotoRec - Recovery de fichiers ==="
            echo "Selectionner le disque dans l'interface..."
            sudo photorec
            ;;
        6)
            SRC=$(whiptail --inputbox "Disque source (ex: /dev/sda):" 8 60 3>&1 1>&2 2>&3)
            DST=$(whiptail --inputbox "Fichier destination (ex: /home/erick/backup.img):" 8 60 3>&1 1>&2 2>&3)
            if [ -n "$SRC" ] && [ -n "$DST" ]; then
                echo "=== DDRescue: $SRC -> $DST ==="
                echo "Ctrl+C pour arreter (reprend automatiquement)"
                sudo ddrescue -f -n "$SRC" "$DST" "${DST}.log"
            fi
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        7)
            echo "=== Reset mot de passe Windows ==="
            echo ""
            echo "Partitions NTFS disponibles:"
            lsblk -o NAME,SIZE,FSTYPE,LABEL | grep ntfs
            echo ""
            PART=$(whiptail --inputbox "Partition Windows (ex: /dev/sda2):" 8 60 3>&1 1>&2 2>&3)
            if [ -n "$PART" ]; then
                MOUNT_DIR=$(mktemp -d)
                sudo mount -t ntfs-3g "$PART" "$MOUNT_DIR"
                SAM_PATH="$MOUNT_DIR/Windows/System32/config/SAM"
                if [ -f "$SAM_PATH" ]; then
                    echo "Fichier SAM trouve!"
                    sudo chntpw -l "$SAM_PATH"
                    echo ""
                    read -p "Editer un utilisateur? (o/n): " EDIT
                    if [ "$EDIT" = "o" ]; then
                        sudo chntpw -u Administrator "$SAM_PATH"
                    fi
                else
                    echo "Fichier SAM non trouve dans $MOUNT_DIR"
                    echo "Verifier le chemin Windows/System32/config/SAM"
                fi
                sudo umount "$MOUNT_DIR"
                rmdir "$MOUNT_DIR"
            fi
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        8)
            echo "=== Partitions NTFS disponibles ==="
            lsblk -o NAME,SIZE,FSTYPE,LABEL | grep -E "ntfs|NAME"
            PART=$(whiptail --inputbox "Partition a monter (ex: /dev/sda2):" 8 60 3>&1 1>&2 2>&3)
            if [ -n "$PART" ]; then
                MOUNT_DIR="/mnt/windows"
                sudo mkdir -p "$MOUNT_DIR"
                sudo mount -t ntfs-3g "$PART" "$MOUNT_DIR"
                echo "Monte sur $MOUNT_DIR"
                nemo "$MOUNT_DIR" &
            fi
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        9)
            DISK=$(whiptail --inputbox "Disque a tester (ex: /dev/sda):" 8 60 3>&1 1>&2 2>&3)
            if [ -n "$DISK" ]; then
                echo "=== Benchmark /dev/$DISK ==="
                echo "--- Lecture sequentielle ---"
                sudo fio --name=seqread --filename="$DISK" --rw=read --bs=1M --size=256M --numjobs=1 --direct=1 --runtime=10 --time_based --output-format=terse | awk -F';' '{print "Read: " $6/1024 " MB/s"}'
            fi
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        Q|q|"")
            exit 0
            ;;
    esac
done
