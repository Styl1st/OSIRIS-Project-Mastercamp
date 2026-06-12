#!/usr/bin/env bash
# =============================================================================
# 01-prepare-system.sh — Préparation de la VM Ubuntu pour le serveur Wazuh
# Rôle : Infrastructure & Déploiement
# Usage : sudo bash 01-prepare-system.sh
# =============================================================================
set -euo pipefail

# ----------- VARIABLES À ADAPTER (subnet VMnet8 réel !) ----------------------
STATIC_IP="192.168.195.134"     # IP du serveur Wazuh
PREFIX="24"                    # Masque /24
GATEWAY="192.168.195.2"        # Passerelle NAT VMware (généralement .2 du subnet)
DNS="8.8.8.8,1.1.1.1"
HOSTNAME="wazuh-server"
# -----------------------------------------------------------------------------

[[ $EUID -eq 0 ]] || { echo "[ERREUR] Lancer avec sudo." >&2; exit 1; }

echo "[1/5] Hostname → ${HOSTNAME}"
hostnamectl set-hostname "${HOSTNAME}"
grep -q "${HOSTNAME}" /etc/hosts || echo "127.0.1.1 ${HOSTNAME}" >> /etc/hosts

echo "[2/5] Mise à jour du système + prérequis"
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq curl tar gnupg apt-transport-https openssh-server

echo "[3/5] Configuration IP statique (netplan)"
IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
echo "    Interface détectée : ${IFACE}"

# Renderer : NetworkManager si Ubuntu Desktop, networkd si Server
if systemctl is-active --quiet NetworkManager; then RENDERER="NetworkManager"; else RENDERER="networkd"; fi

cat > /etc/netplan/99-wazuh-static.yaml <<EOF
network:
  version: 2
  renderer: ${RENDERER}
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses: [${STATIC_IP}/${PREFIX}]
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses: [${DNS//,/, }]
EOF
chmod 600 /etc/netplan/99-wazuh-static.yaml
netplan apply
echo "    IP appliquée : ${STATIC_IP}"

echo "[4/5] Vérification des ressources"
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
DISK_GB=$(df -BG / | awk 'NR==2{gsub("G","",$4); print $4}')
CPUS=$(nproc)
echo "    CPU: ${CPUS} | RAM: ${RAM_GB} Go | Disque libre: ${DISK_GB} Go"
[[ ${RAM_GB} -ge 7 ]]  || echo "    [ATTENTION] <8 Go RAM : utiliser l'option -i à l'installation."
[[ ${DISK_GB} -ge 40 ]] || echo "    [ATTENTION] <40 Go libres : rétention des logs limitée."

echo "[5/5] Test connectivité Internet"
curl -s --max-time 10 https://packages.wazuh.com >/dev/null && echo "    OK : packages.wazuh.com joignable." \
  || { echo "[ERREUR] Pas d'accès à packages.wazuh.com" >&2; exit 1; }

echo ""
echo "=== Préparation terminée. Étape suivante : sudo bash 02-install-wazuh-server.sh ==="