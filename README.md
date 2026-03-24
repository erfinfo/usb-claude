# USB-Claude - Station de travail MSP portable

**EFC Informatique** | Erick Fortin | erick@efcinfo.com
**Version:** 1.0 | **Date:** 2026-03-24

## Description

Cle USB bootable 234 GB qui transforme **n'importe quelle machine** en station de travail MSP complete. Boot UEFI, detection reseau automatique (WiFi, Ethernet, Hotspot), persistance des donnees entre les sessions.

## Outils inclus

| Categorie | Outils |
|-----------|--------|
| **IA** | Claude Code 2.1.81 (`--dangerously-skip-permissions`), VS Codium + extension |
| **Dev** | Git, GitHub CLI, Python 3, Node.js, npm, vim, nano |
| **Reseau** | nmap, wireshark, tcpdump, mtr, iperf3, arp-scan, netdiscover, wavemon |
| **Active Directory** | samba-tool, ldapsearch, adcli, realmd, sssd, krb5-user, winbind |
| **Remote** | Remmina (RDP/VNC), SSH, tmux, screen |
| **Disques** | GParted, testdisk, photorec, ddrescue, smartmontools, chntpw |
| **VPN** | NetBird, WireGuard, OpenVPN |
| **Monitoring** | htop, btop, iotop, nethogs, bmon |
| **Fichiers** | Midnight Commander, rsync, rclone, smbclient, sshfs |
| **Web** | Firefox ESR |
| **Firmwares** | Intel WiFi, Realtek, Broadcom, Atheros, AMD GPU, Intel Sound |

## Lanceurs Desktop (11 icones)

| Icone | Nom | Action |
|-------|-----|--------|
| Claude Code | IA assistant mode autonome | `claude --dangerously-skip-permissions` |
| VS Codium | Editeur de code | Ouvre ~/projets |
| Outils Reseau | Diagnostic reseau | Menu: nmap, wireshark, arp-scan, WiFi, iperf3 |
| Active Directory | Outils AD | Menu: ldapsearch, realm join, kinit, DC discovery |
| Disques & Recovery | Outils disques | Menu: GParted, SMART, testdisk, ddrescue |
| Disk Repair Wizard | Diagnostic + reparation | Auto-diagnostic, fsck, boot repair, clone |
| Backup Client | Backup avec MC | Liste disques, monte source, ouvre Midnight Commander |
| VPN NetBird | Connexion VPN | Menu: connect, setup keys EFC/CAO/SPIN/Regie |
| Remote Desktop | RDP/VNC | Remmina |
| Projets GitHub | Gestionnaire fichiers | Ouvre ~/projets |
| EFC Toolkit | Menu principal | Tous les outils en un menu |

## Architecture

### Partitions USB

| Partition | Taille | Type | Label | Usage |
|-----------|--------|------|-------|-------|
| sdd1 | 512 MB | FAT32 (ESP) | EFI | Boot UEFI + GRUB |
| sdd2 | 10 GB | ext4 | USB-CLAUDE | Systeme live (squashfs read-only) |
| sdd3 | ~224 GB | ext4 (no journal) | persistence | Home, configs, repos Git |

**Note:** La partition persistence est formatee **sans journal** (`-O ^has_journal`) pour eviter la corruption lors des deconnexions USB.

### Boot Flow

```
UEFI → GRUB (search --label USB-CLAUDE) → Linux kernel + initrd
  → Mount squashfs (systeme read-only)
  → live-boot detecte label "persistence" → monte overlay
  → NetworkManager auto-detecte interfaces
  → Cinnamon desktop → first-boot wizard (1ere fois)
```

### Persistence (overlay union)

Le fichier `persistence.conf` definit ce qui est persistant:
```
/home union       # Donnees utilisateur, repos, credentials
/etc union        # Configs systeme modifiees
/var/lib union    # Donnees services (samba, sssd, etc.)
/usr/local union  # Scripts EFC toolkit
/root union       # Config root
```

## Build

### Pre-requis

- Debian 13 (Trixie) x86_64
- ~15 GB d'espace disque libre dans `/projets/`
- Acces root (sudo)
- Connexion Internet

### Construire l'ISO

```bash
# Build complet (~20-30 minutes)
sudo ./build-usb-claude.sh

# Rebuild rapide (reutilise le chroot existant)
sudo ./build-usb-claude.sh --skip-debootstrap

# Nettoyer et rebuild from scratch
sudo ./build-usb-claude.sh --clean
```

### Ecrire sur la cle USB

```bash
# ATTENTION: efface toutes les donnees sur la cle!
sudo ./write-to-usb.sh /dev/sdX
```

### Post-ecriture: installer la persistence

Apres `write-to-usb.sh`, la persistence est formatee mais vide.
Pour installer Claude Code et les outils sur la persistence:

```bash
sudo mount /dev/sdX3 /mnt
# Copier Claude Code, .bashrc, .gitconfig, lanceurs, scripts...
# (voir section "Maintenance" ci-dessous)
sudo umount /mnt
```

## Utilisation

1. Brancher la cle USB sur n'importe quelle machine
2. Booter dessus (F12 / F2 au demarrage → selectionner USB)
3. Login: `erick` (pas de mot de passe)
4. Au premier boot, le wizard configure Claude Code, GitHub, Git, et NetBird
5. Utiliser les icones sur le bureau pour acceder aux outils

### Menus de boot GRUB

| Option | Description |
|--------|-------------|
| USB-Claude - EFC Informatique | Mode normal avec persistance |
| Sans Persistance | Mode live clean (rien n'est sauvegarde) |
| Mode Texte (Recovery) | CLI seulement, avec persistance |
| Mode RAM | Copie tout en RAM (rapide, deconnexion USB possible) |

## Structure du projet

```
usb-claude/
├── build-usb-claude.sh              # Script de build principal
├── write-to-usb.sh                  # Ecriture sur cle USB
├── README.md                        # Ce fichier
├── .gitignore                       # Exclut ISO, chroot, build, squashfs
├── configs/
│   ├── persistence.conf             # Config overlay persistence
│   └── NetworkManager/
│       └── NetworkManager.conf      # Auto-connect reseau
├── desktop/                         # 11 lanceurs .desktop
│   ├── claude-code.desktop
│   ├── vs-codium.desktop
│   ├── outils-reseau.desktop
│   ├── active-directory.desktop
│   ├── disques-recovery.desktop
│   ├── disk-repair.desktop
│   ├── backup-client.desktop
│   ├── vpn-netbird.desktop
│   ├── remote-desktop.desktop
│   ├── projets-github.desktop
│   └── efc-toolkit.desktop
├── scripts/
│   ├── first-boot.sh               # Wizard premier demarrage
│   └── efc-toolkit/                 # 8 scripts interactifs
│       ├── network-tools.sh         # nmap, wireshark, arp-scan, WiFi
│       ├── ad-tools.sh              # ldapsearch, realm join, kinit
│       ├── disk-tools.sh            # GParted, SMART, testdisk
│       ├── disk-repair-wizard.sh    # Diagnostic complet + reparation
│       ├── backup-client.sh         # Backup avec Midnight Commander
│       ├── vpn-tools.sh             # NetBird connect/config
│       ├── system-info.sh           # Rapport hardware/reseau
│       └── efc-toolkit.sh           # Menu principal
├── branding/                        # (a venir: wallpaper, plymouth)
│   ├── wallpaper.png
│   └── plymouth/efc-theme/
│
│ # Fichiers generes (dans .gitignore):
├── chroot/                          # Systeme Debian debootstrap (~4 GB)
├── build/                           # Structure ISO assemblee (~1.4 GB)
├── filesystem.squashfs              # Systeme compresse (~1.3 GB)
└── usb-claude-*.iso                 # ISO bootable (~1.4 GB)
```

## Problemes connus et solutions

### Controleur USB CBM2199

La cle USB generique avec chipset CBM2199 corrompt facilement le journal ext4.
**Solution:** Persistence formatee sans journal (`mkfs.ext4 -O ^has_journal`).

### GRUB "vmlinuz not found"

GRUB cherche le kernel sur la partition EFI au lieu de la partition Live.
**Solution:** `search --label USB-CLAUDE --set=root` dans grub.cfg.

### Persistence ne monte pas

Si le filesystem persistence est corrompu:
```bash
sudo e2fsck -f -y /dev/sdX3
```

## Maintenance

### Ajouter un outil au toolkit

1. Creer le script dans `scripts/efc-toolkit/mon-outil.sh`
2. Creer le lanceur dans `desktop/mon-outil.desktop`
3. Monter la persistence: `sudo mount /dev/sdX3 /mnt`
4. Copier: `sudo cp scripts/... /mnt/usr/local/bin/efc-mon-outil`
5. Copier: `sudo cp desktop/... /mnt/home/erick/Desktop/`
6. `sync && sudo umount /mnt`

### Mettre a jour Claude Code

```bash
# Sur la machine bootee avec USB-Claude:
curl -fsSL https://claude.ai/install.sh | bash
```

### Rebuilder l'ISO

```bash
cd /projets/usb-claude
sudo ./build-usb-claude.sh --skip-debootstrap
sudo ./write-to-usb.sh /dev/sdX
# Puis reinstaller la persistence (Claude Code, scripts, etc.)
```

## Changelog

### v1.0 (2026-03-24)
- Build initial: Debian 13 Trixie + Cinnamon
- 150+ paquets MSP (reseau, AD, disques, dev, monitoring)
- Claude Code 2.1.81, VS Codium, GitHub CLI, NetBird
- 11 lanceurs desktop, 8 scripts toolkit interactifs
- Disk Repair Wizard (diagnostic SMART + fsck + boot repair + clone)
- Backup Client (Midnight Commander)
- Persistence ext4 sans journal (resistant deconnexions USB)
- Boot UEFI avec GRUB (search by label)
