#!/bin/bash
# =============================================================================
# EFC Network Tools - Menu interactif d'outils reseau
# =============================================================================

while true; do
    CHOICE=$(whiptail --title "EFC - Outils Reseau" --menu "Choisir un outil:" 22 70 12 \
        "1" "Scan reseau rapide (arp-scan)" \
        "2" "Scan de ports (nmap)" \
        "3" "Decouverte reseau (netdiscover)" \
        "4" "Analyse WiFi (wavemon)" \
        "5" "Test de bande passante (iperf3)" \
        "6" "Traceroute" \
        "7" "Test DNS (dig)" \
        "8" "Wireshark (capture paquets)" \
        "9" "Interfaces reseau (ip addr)" \
        "10" "Connexions actives (ss/netstat)" \
        "11" "Monitoring bande passante (nethogs)" \
        "Q" "Quitter" \
        3>&1 1>&2 2>&3)

    case "$CHOICE" in
        1)
            echo "=== Scan ARP du reseau local ==="
            IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
            SUBNET=$(ip -4 addr show "$IFACE" | grep inet | awk '{print $2}')
            echo "Interface: $IFACE | Subnet: $SUBNET"
            sudo arp-scan --localnet --interface="$IFACE" 2>/dev/null || sudo arp-scan --localnet
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        2)
            TARGET=$(whiptail --inputbox "Adresse IP ou reseau a scanner:" 8 60 "192.168.1.0/24" 3>&1 1>&2 2>&3)
            [ -n "$TARGET" ] && { echo "=== Scan nmap de $TARGET ==="; sudo nmap -sV -O --top-ports 100 "$TARGET"; }
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        3)
            echo "=== Decouverte reseau (Ctrl+C pour arreter) ==="
            sudo netdiscover -P -N
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        4)
            wavemon
            ;;
        5)
            MODE=$(whiptail --menu "Mode iperf3:" 10 50 2 "server" "Demarrer en mode serveur" "client" "Se connecter a un serveur" 3>&1 1>&2 2>&3)
            if [ "$MODE" = "server" ]; then
                echo "Serveur iperf3 demarre sur port 5201 (Ctrl+C pour arreter)"
                iperf3 -s
            else
                TARGET=$(whiptail --inputbox "IP du serveur iperf3:" 8 60 3>&1 1>&2 2>&3)
                [ -n "$TARGET" ] && iperf3 -c "$TARGET"
            fi
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        6)
            TARGET=$(whiptail --inputbox "Destination:" 8 60 "8.8.8.8" 3>&1 1>&2 2>&3)
            [ -n "$TARGET" ] && mtr --report "$TARGET"
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        7)
            DOMAIN=$(whiptail --inputbox "Domaine a verifier:" 8 60 "google.com" 3>&1 1>&2 2>&3)
            [ -n "$DOMAIN" ] && { dig "$DOMAIN" ANY; echo "---"; nslookup "$DOMAIN"; }
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        8)
            sudo wireshark &
            ;;
        9)
            echo "=== Interfaces reseau ==="
            ip addr show
            echo ""
            echo "=== Routes ==="
            ip route show
            echo ""
            echo "=== DNS ==="
            cat /etc/resolv.conf
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        10)
            echo "=== Connexions actives ==="
            ss -tunlp
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        11)
            sudo nethogs
            ;;
        Q|q|"")
            exit 0
            ;;
    esac
done
