#!/bin/bash
# =============================================================================
# USB-Claude - First Boot Wizard
# Configuration initiale au premier demarrage
# =============================================================================

FLAG_FILE="$HOME/.config/usb-claude-configured"

# Si deja configure, ne pas afficher
if [ -f "$FLAG_FILE" ]; then
    exit 0
fi

# Attendre que le desktop soit charge
sleep 3

export DISPLAY=:0

# === BIENVENUE ===
whiptail --title "USB-Claude - EFC Informatique" --msgbox \
    "Bienvenue sur USB-Claude!\n\nStation de travail MSP portable\nEFC Informatique - Erick Fortin\n\nCe wizard va configurer:\n  1. Connexion reseau\n  2. Claude Code (IA)\n  3. GitHub CLI\n  4. Git\n  5. VPN NetBird\n\nAppuyez sur OK pour commencer." 18 55

# === ETAPE 1: RESEAU ===
whiptail --title "Etape 1/5 - Reseau" --msgbox \
    "Verification de la connexion reseau...\n\nNetworkManager detecte automatiquement\nles interfaces WiFi et Ethernet." 12 50

# Verifier si connecte
if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
    IP=$(ip route get 8.8.8.8 | awk '{print $7; exit}')
    whiptail --title "Reseau OK" --msgbox "Connecte a Internet!\n\nIP: $IP" 10 40
else
    # Proposer connexion WiFi
    if whiptail --title "Pas de connexion" --yesno "Pas de connexion Internet.\n\nSe connecter au WiFi?" 10 40; then
        gnome-terminal --title="Connexion WiFi" -- bash -c "
            echo '=== Reseaux WiFi disponibles ==='
            nmcli device wifi list
            echo ''
            read -p 'SSID: ' SSID
            read -sp 'Mot de passe: ' PASS
            echo ''
            nmcli device wifi connect \"\$SSID\" password \"\$PASS\"
            sleep 3
            if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
                echo 'Connecte!'
            else
                echo 'Echec de connexion.'
            fi
            read -p 'Appuyer sur Entree...'
        "
        sleep 5
    fi
fi

# === ETAPE 2: CLAUDE CODE ===
if whiptail --title "Etape 2/5 - Claude Code" --yesno \
    "Configurer Claude Code?\n\nCeci va ouvrir un navigateur pour\nvous connecter a votre compte Anthropic\n(CloudMax)." 12 50; then

    gnome-terminal --title="Claude Code Login" -- bash -c "
        echo '=== Configuration Claude Code ==='
        echo ''
        if command -v claude &>/dev/null; then
            echo 'Claude Code detecte. Lancement du login...'
            claude /login
        else
            echo 'Claude Code non installe. Installation...'
            curl -fsSL https://claude.ai/install.sh | bash
            echo ''
            echo 'Installation terminee. Lancement du login...'
            claude /login
        fi
        echo ''
        read -p 'Appuyer sur Entree quand termine...'
    "
    sleep 2
fi

# === ETAPE 3: GITHUB CLI ===
if whiptail --title "Etape 3/5 - GitHub CLI" --yesno \
    "Configurer GitHub CLI?\n\nCeci va vous permettre de cloner\net push sur vos repos GitHub." 12 50; then

    gnome-terminal --title="GitHub CLI Login" -- bash -c "
        echo '=== Configuration GitHub CLI ==='
        echo ''
        gh auth login
        echo ''
        echo '=== Verification ==='
        gh auth status
        echo ''
        read -p 'Appuyer sur Entree quand termine...'
    "
    sleep 2
fi

# === ETAPE 4: GIT ===
whiptail --title "Etape 4/5 - Git" --msgbox \
    "Git est pre-configure avec:\n\n  Nom:   Erick Fortin\n  Email: erick@efcinfo.com\n\nModifiable avec: git config --global" 12 50

# === ETAPE 5: VPN NETBIRD ===
if whiptail --title "Etape 5/5 - VPN NetBird" --yesno \
    "Configurer le VPN NetBird?\n\nCeci va connecter cette machine\nau reseau VPN EFC." 12 50; then

    gnome-terminal --title="VPN NetBird" -- bash -c "
        echo '=== Configuration NetBird VPN ==='
        echo ''
        echo 'Setup Keys disponibles:'
        echo '1) EFC (par defaut)'
        echo '2) CAO'
        echo '3) SPIN'
        echo '4) Regie'
        echo '5) Forestville'
        echo ''
        read -p 'Choix (1-5) [1]: ' CHOICE
        CHOICE=\${CHOICE:-1}
        case \$CHOICE in
            1) KEY='9242398C-DB3C-4DC5-8C44-FA2FC55BEACC' ;;
            2) KEY='A7E6D900-DEB6-42DA-81E9-24C21DAC05BB' ;;
            3) KEY='33CD6E2E-2019-4C9C-8986-249E63F971B7' ;;
            4) KEY='161EA186-5C52-4EB1-B819-D2055D0B548D' ;;
            5) KEY='D872C01E-56C3-420B-9F70-69A424742E96' ;;
        esac
        sudo netbird up --setup-key \"\$KEY\"
        sleep 3
        netbird status
        echo ''
        read -p 'Appuyer sur Entree quand termine...'
    "
    sleep 2
fi

# === TERMINER ===
mkdir -p "$(dirname "$FLAG_FILE")"
date > "$FLAG_FILE"

whiptail --title "Configuration terminee!" --msgbox \
    "USB-Claude est pret!\n\nTes outils sont sur le bureau:\n  - Claude Code (IA)\n  - VS Codium (editeur)\n  - Outils Reseau\n  - Active Directory\n  - Disques & Recovery\n  - VPN NetBird\n  - Remote Desktop\n  - EFC Toolkit\n\nBon travail!\nEFC Informatique - erick@efcinfo.com" 20 50
