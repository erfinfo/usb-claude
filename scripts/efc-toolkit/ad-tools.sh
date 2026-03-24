#!/bin/bash
# =============================================================================
# EFC Active Directory Tools - Menu interactif
# =============================================================================

while true; do
    CHOICE=$(whiptail --title "EFC - Active Directory Tools" --menu "Choisir un outil:" 20 70 10 \
        "1" "Joindre un domaine AD (realm join)" \
        "2" "Recherche LDAP (ldapsearch)" \
        "3" "Lister les utilisateurs AD" \
        "4" "Lister les groupes AD" \
        "5" "Info domaine (realm list)" \
        "6" "Ticket Kerberos (kinit)" \
        "7" "Status Kerberos (klist)" \
        "8" "Decouvrir le controleur de domaine" \
        "9" "Test de connectivite AD" \
        "Q" "Quitter" \
        3>&1 1>&2 2>&3)

    case "$CHOICE" in
        1)
            DOMAIN=$(whiptail --inputbox "Nom du domaine AD (ex: municao.local):" 8 60 3>&1 1>&2 2>&3)
            if [ -n "$DOMAIN" ]; then
                ADMIN=$(whiptail --inputbox "Compte admin AD (ex: Administrator):" 8 60 "Administrator" 3>&1 1>&2 2>&3)
                echo "=== Joindre le domaine $DOMAIN ==="
                sudo realm join -v "$DOMAIN" -U "$ADMIN"
            fi
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        2)
            SERVER=$(whiptail --inputbox "IP du serveur LDAP (DC):" 8 60 3>&1 1>&2 2>&3)
            BASEDN=$(whiptail --inputbox "Base DN (ex: DC=municao,DC=local):" 8 60 3>&1 1>&2 2>&3)
            FILTER=$(whiptail --inputbox "Filtre LDAP:" 8 60 "(objectClass=user)" 3>&1 1>&2 2>&3)
            if [ -n "$SERVER" ] && [ -n "$BASEDN" ]; then
                echo "=== Recherche LDAP ==="
                ldapsearch -x -H "ldap://$SERVER" -b "$BASEDN" "$FILTER" cn sAMAccountName mail
            fi
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        3)
            SERVER=$(whiptail --inputbox "IP du serveur LDAP (DC):" 8 60 3>&1 1>&2 2>&3)
            BASEDN=$(whiptail --inputbox "Base DN (ex: DC=municao,DC=local):" 8 60 3>&1 1>&2 2>&3)
            if [ -n "$SERVER" ] && [ -n "$BASEDN" ]; then
                echo "=== Utilisateurs AD ==="
                ldapsearch -x -H "ldap://$SERVER" -b "$BASEDN" \
                    "(&(objectClass=user)(objectCategory=person))" \
                    cn sAMAccountName mail memberOf | grep -E "^(dn|cn|sAMAccountName|mail):"
            fi
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        4)
            SERVER=$(whiptail --inputbox "IP du serveur LDAP (DC):" 8 60 3>&1 1>&2 2>&3)
            BASEDN=$(whiptail --inputbox "Base DN (ex: DC=municao,DC=local):" 8 60 3>&1 1>&2 2>&3)
            if [ -n "$SERVER" ] && [ -n "$BASEDN" ]; then
                echo "=== Groupes AD ==="
                ldapsearch -x -H "ldap://$SERVER" -b "$BASEDN" \
                    "(objectClass=group)" cn description | grep -E "^(dn|cn|description):"
            fi
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        5)
            echo "=== Domaines configures ==="
            realm list
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        6)
            USER=$(whiptail --inputbox "Utilisateur Kerberos (ex: admin@MUNICAO.LOCAL):" 8 60 3>&1 1>&2 2>&3)
            [ -n "$USER" ] && kinit "$USER"
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        7)
            echo "=== Tickets Kerberos ==="
            klist
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        8)
            DOMAIN=$(whiptail --inputbox "Nom du domaine (ex: municao.local):" 8 60 3>&1 1>&2 2>&3)
            if [ -n "$DOMAIN" ]; then
                echo "=== Decouverte DC pour $DOMAIN ==="
                echo "--- DNS SRV ---"
                dig +short _ldap._tcp."$DOMAIN" SRV
                dig +short _kerberos._tcp."$DOMAIN" SRV
                echo "--- realm discover ---"
                realm discover "$DOMAIN" 2>/dev/null || echo "(realm discover echoue)"
            fi
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        9)
            SERVER=$(whiptail --inputbox "IP du controleur de domaine:" 8 60 3>&1 1>&2 2>&3)
            if [ -n "$SERVER" ]; then
                echo "=== Test de connectivite AD vers $SERVER ==="
                echo "--- Ping ---"
                ping -c 3 "$SERVER"
                echo "--- Ports AD ---"
                for port in 53 88 135 389 445 636 3268 3269; do
                    timeout 2 bash -c "echo >/dev/tcp/$SERVER/$port" 2>/dev/null && echo "Port $port: OUVERT" || echo "Port $port: FERME"
                done
            fi
            read -p "Appuyer sur Entree pour continuer..."
            ;;
        Q|q|"")
            exit 0
            ;;
    esac
done
