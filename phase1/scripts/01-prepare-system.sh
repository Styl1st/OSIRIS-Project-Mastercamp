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

echo "[3/5] Configuration IP statique"
IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
[[ -n "${IFACE}" ]] || IFACE=$(ip -o link show | awk -F': ' '$2!="lo"{print $2; exit}')
echo "    Interface détectée : ${IFACE}"

if systemctl is-active --quiet NetworkManager; then
  # Ubuntu Desktop → NetworkManager (nmcli). Ne PAS mélanger avec netplan/networkd.
  rm -f /etc/netplan/99-wazuh-static.yaml   # nettoyage d'un éventuel essai précédent
  CON=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v i="${IFACE}" '$2==i{print $1; exit}')
  [[ -n "${CON}" ]] || CON=$(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="802-3-ethernet"{print $1; exit}')
  echo "    Connexion NetworkManager : ${CON}"
  nmcli connection modify "${CON}" \
    ipv4.method manual \
    ipv4.addresses "${STATIC_IP}/${PREFIX}" \
    ipv4.gateway "${GATEWAY}" \
    ipv4.dns "${DNS//,/ }"
  nmcli connection up "${CON}" >/dev/null
else
  # Ubuntu Server → netplan/systemd-networkd
  cat > /etc/netplan/99-wazuh-static.yaml <<EOF
network:
  version: 2
  renderer: networkd
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
fi
sleep 3
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
