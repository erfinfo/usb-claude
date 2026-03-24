#!/bin/bash
# =============================================================================
# EFC System Info - Rapport complet du systeme
# =============================================================================

echo "============================================"
echo "  EFC Informatique - Rapport Systeme"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

echo "=== HARDWARE ==="
echo "Machine:    $(sudo dmidecode -s system-manufacturer 2>/dev/null) $(sudo dmidecode -s system-product-name 2>/dev/null)"
echo "Serial:     $(sudo dmidecode -s system-serial-number 2>/dev/null)"
echo "CPU:        $(lscpu | grep 'Model name' | sed 's/Model name: *//')"
echo "Coeurs:     $(nproc) ($(lscpu | grep 'Socket(s)' | awk '{print $2}') socket(s))"
echo "RAM:        $(free -h | awk '/Mem:/ {print $2}') total, $(free -h | awk '/Mem:/ {print $3}') utilise"
echo "BIOS:       $(sudo dmidecode -s bios-vendor 2>/dev/null) $(sudo dmidecode -s bios-version 2>/dev/null)"
echo ""

echo "=== DISQUES ==="
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MODEL | grep -v loop
echo ""
echo "--- Espace ---"
df -hT | grep -v tmpfs | grep -v loop
echo ""

echo "=== RESEAU ==="
echo "--- Interfaces ---"
ip -br addr show | grep -v lo
echo ""
echo "--- WiFi ---"
nmcli device wifi list 2>/dev/null || echo "(Pas de WiFi detecte)"
echo ""
echo "--- Passerelle ---"
ip route | grep default
echo ""
echo "--- DNS ---"
grep nameserver /etc/resolv.conf
echo ""

echo "=== USB ==="
lsusb
echo ""

echo "=== PCI (Cartes reseau) ==="
lspci | grep -iE "network|ethernet|wifi|wireless"
echo ""

echo "=== TEMPERATURES ==="
sensors 2>/dev/null || echo "(lm-sensors non installe)"
echo ""

echo "=== OS ==="
cat /etc/os-release | head -4
echo "Kernel:     $(uname -r)"
echo "Hostname:   $(hostname)"
echo "Uptime:     $(uptime -p)"
echo ""

echo "============================================"
echo "  Rapport genere: $(date)"
echo "  EFC Informatique - erick@efcinfo.com"
echo "============================================"

read -p "Appuyer sur Entree pour continuer..."
