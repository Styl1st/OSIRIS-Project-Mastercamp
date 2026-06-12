#!/usr/bin/env bash
# =============================================================================
# 04-enable-syslog-collection.sh — Réception syslog (firewall / switch, agentless)
# Ajoute un listener syslog 514/udp au manager Wazuh.
# Usage : sudo bash 04-enable-syslog-collection.sh
# =============================================================================
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "[ERREUR] Lancer avec sudo." >&2; exit 1; }

OSSEC_CONF="/var/ossec/etc/ossec.conf"
ALLOWED_NET="192.168.195.0/24"   # ← adapter au subnet VMnet8 réel

if grep -q "<connection>syslog</connection>" "$OSSEC_CONF"; then
  echo "[INFO] Listener syslog déjà configuré. Rien à faire."
  exit 0
fi

echo "[1/3] Sauvegarde de ossec.conf"
cp "$OSSEC_CONF" "${OSSEC_CONF}.bak.$(date +%Y%m%d-%H%M%S)"

echo "[2/3] Ajout du bloc <remote> syslog (514/udp, réseau autorisé : ${ALLOWED_NET})"
cat >> "$OSSEC_CONF" <<EOF

<!-- Réception syslog agentless : firewall, switch (ajouté par 04-enable-syslog-collection.sh) -->
<ossec_config>
  <remote>
    <connection>syslog</connection>
    <port>514</port>
    <protocol>udp</protocol>
    <allowed-ips>${ALLOWED_NET}</allowed-ips>
  </remote>
</ossec_config>
EOF

echo "[3/3] Redémarrage du manager"
systemctl restart wazuh-manager
sleep 5
systemctl is-active --quiet wazuh-manager && echo "[OK] Manager redémarré." \
  || { echo "[ERREUR] Manager KO → restaurer le backup et voir journalctl -u wazuh-manager"; exit 1; }

ss -uln "( sport = :514 )" | grep -q 514 && echo "[OK] Port 514/udp en écoute." || echo "[ATTENTION] 514/udp non visible."
echo ""
echo "Côté équipements : configurer l'envoi syslog vers $(hostname -I | awk '{print $1}'):514 (UDP)."
echo "  - pfSense : Status > System Logs > Settings > Remote Logging"
echo "  - Switch Cisco : logging host <IP> / logging trap informational"
