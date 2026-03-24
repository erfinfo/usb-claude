#!/bin/bash
# =============================================================================
# EFC Toolkit - Menu principal
# Boite a outils MSP complete pour techniciens sur le terrain
# =============================================================================

TOOLKIT_DIR="/usr/local/bin"

while true; do
    CHOICE=$(whiptail --title "EFC Toolkit - Station MSP Portable" --menu \
        "USB-Claude v1.0 | EFC Informatique" 22 70 12 \
        "1" "Outils Reseau (nmap, wireshark, scan, WiFi)" \
        "2" "Active Directory (LDAP, Kerberos, realm)" \
        "3" "Disques & Recovery (GParted, testdisk, SMART)" \
        "4" "VPN NetBird (connexion infrastructure)" \
        "5" "Remote Desktop (RDP/VNC via Remmina)" \
        "6" "Info Systeme (rapport complet)" \
        "7" "Claude Code (IA assistant)" \
        "8" "VS Codium (editeur de code)" \
        "9" "Terminal (bash)" \
        "10" "Gestionnaire de fichiers" \
        "11" "Navigateur web" \
        "Q" "Quitter" \
        3>&1 1>&2 2>&3)

    case "$CHOICE" in
        1)  "$TOOLKIT_DIR/efc-network-tools" ;;
        2)  "$TOOLKIT_DIR/efc-ad-tools" ;;
        3)  "$TOOLKIT_DIR/efc-disk-tools" ;;
        4)  "$TOOLKIT_DIR/efc-vpn" ;;
        5)  remmina & ;;
        6)  "$TOOLKIT_DIR/efc-system-info" ;;
        7)  claude --dangerously-skip-permissions ;;
        8)  codium ~/projets & ;;
        9)  bash ;;
        10) nemo ~/projets & ;;
        11) firefox-esr & ;;
        Q|q|"")
            exit 0
            ;;
    esac
done
