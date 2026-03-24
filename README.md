# USB-Claude - Station de travail MSP portable

**EFC Informatique** | Erick Fortin | erick@efcinfo.com

## Description

Cle USB bootable 234 GB qui transforme n'importe quelle machine en station de travail MSP complete avec:

- **Claude Code** (IA assistant en mode autonome)
- **VS Codium** (editeur de code avec extension Claude)
- **Git / GitHub CLI** (gestion de code)
- **Outils reseau** (nmap, wireshark, arp-scan, WiFi analyzer)
- **Active Directory** (ldapsearch, realm join, Kerberos)
- **Disques & Recovery** (GParted, testdisk, chntpw, ddrescue)
- **VPN NetBird** (acces infrastructure clients)
- **Remote Desktop** (RDP/VNC via Remmina)
- **Persistance** des donnees, configs et repos entre les sessions

## Pre-requis pour le build

- Debian 13 (Trixie) x86_64
- ~15 GB d'espace disque libre
- Acces root (sudo)
- Connexion Internet

## Build

```bash
# Construire l'ISO (~20-30 minutes)
sudo ./build-usb-claude.sh

# Ecrire sur la cle USB (ATTENTION: efface toutes les donnees!)
sudo ./write-to-usb.sh /dev/sdX
```

## Options du build script

```bash
sudo ./build-usb-claude.sh --clean            # Nettoyer avant de rebuild
sudo ./build-usb-claude.sh --skip-debootstrap  # Reutiliser le chroot existant
```

## Utilisation

1. Brancher la cle USB sur n'importe quelle machine
2. Booter dessus (F12 / F2 au demarrage -> selectionner USB)
3. Au premier boot, le wizard configure Claude Code, GitHub, Git, et NetBird
4. Utiliser les icones sur le bureau pour acceder aux outils

## Structure des partitions

| Partition | Taille | Usage |
|-----------|--------|-------|
| EFI | 512 MB | Boot UEFI |
| Live | 10 GB | Systeme Debian live (read-only) |
| Persistence | ~224 GB | Home, configs, repos Git |

## Menus de boot

1. **USB-Claude** - Mode normal avec persistance
2. **Sans Persistance** - Mode live clean (aucune sauvegarde)
3. **Mode Texte** - Recovery en ligne de commande
4. **Mode RAM** - Copie tout en RAM (rapide, pas de persistance)
