#!/bin/bash
# =============================================================================
# EFC VPN Tools - Gestion NetBird VPN
# =============================================================================

while true; do
    # Status actuel
    NB_STATUS="Inconnu"
    if command -v netbird &>/dev/null; then
        NB_STATUS=$(netbird status 2>/dev/null | head -1 || echo "Non connecte")
    fi

    CHOICE=$(whiptail --title "EFC - VPN NetBird ($NB_STATUS)" --menu "Choisir une action:" 18 70 8 \
        "1" "Connecter le VPN (netbird up)" \
        "2" "Deconnecter le VPN (netbird down)" \
        "3" "Status VPN" \
        "4" "Configurer avec setup key" \
        "5" "Lister les peers connectes" \
        "6" "Ping un peer NetBird" \
        "7" "Logs NetBird" \
        "Q" "Quitter" \
        3>&1 1>&2 2>&3)

    case "$CHOICE" in
        1)
            echo "=== Connexion NetBird ==="
            sudo netbird up
            sleep 2
            netbird status
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        2)
            sudo netbird down
            echo "VPN deconnecte."
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        3)
            echo "=== Status NetBird ==="
            netbird status
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        4)
            echo "=== Setup Keys EFC ==="
            echo "1) EFC      - 9242398C-DB3C-4DC5-8C44-FA2FC55BEACC"
            echo "2) CAO      - A7E6D900-DEB6-42DA-81E9-24C21DAC05BB"
            echo "3) SPIN     - 33CD6E2E-2019-4C9C-8986-249E63F971B7"
            echo "4) Regie    - 161EA186-5C52-4EB1-B819-D2055D0B548D"
            echo "5) Foresti. - D872C01E-56C3-420B-9F70-69A424742E96"
            echo "6) Custom"
            echo ""
            read -p "Choix (1-6): " KEY_CHOICE
            case "$KEY_CHOICE" in
                1) SETUP_KEY="9242398C-DB3C-4DC5-8C44-FA2FC55BEACC" ;;
                2) SETUP_KEY="A7E6D900-DEB6-42DA-81E9-24C21DAC05BB" ;;
                3) SETUP_KEY="33CD6E2E-2019-4C9C-8986-249E63F971B7" ;;
                4) SETUP_KEY="161EA186-5C52-4EB1-B819-D2055D0B548D" ;;
                5) SETUP_KEY="D872C01E-56C3-420B-9F70-69A424742E96" ;;
                6) read -p "Setup key: " SETUP_KEY ;;
                *) SETUP_KEY="" ;;
            esac
            if [ -n "$SETUP_KEY" ]; then
                sudo netbird up --setup-key "$SETUP_KEY"
                sleep 2
                netbird status
            fi
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        5)
            echo "=== Peers NetBird ==="
            netbird status --detail 2>/dev/null || netbird status
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        6)
            PEER=$(whiptail --inputbox "IP du peer NetBird:" 8 60 3>&1 1>&2 2>&3)
            [ -n "$PEER" ] && ping -c 5 "$PEER"
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        7)
            echo "=== Logs NetBird (derniers 50 lignes) ==="
            sudo journalctl -u netbird -n 50 --no-pager
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        Q|q|"")
            exit 0
            ;;
    esac
done
