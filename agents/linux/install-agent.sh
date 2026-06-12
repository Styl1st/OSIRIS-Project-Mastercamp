#!/usr/bin/env bash
# =============================================================================
# install-agent.sh — Installe l'agent Wazuh sur une machine Linux (Debian/Ubuntu)
# Rôle : Agents & Intégrations
# Usage : sudo WAZUH_MANAGER=192.168.195.134 bash install-agent.sh
#         (optionnel : AGENT_NAME=srv-web AGENT_GROUP=linux)
# =============================================================================
set -euo pipefail

WAZUH_MANAGER="${WAZUH_MANAGER:-192.168.195.134}"
AGENT_NAME="${AGENT_NAME:-$(hostname)}"
AGENT_GROUP="${AGENT_GROUP:-linux}"

[[ $EUID -eq 0 ]] || { echo "[ERREUR] Lancer avec sudo." >&2; exit 1; }

echo "[1/3] Ajout du dépôt Wazuh"
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg --yes
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
  > /etc/apt/sources.list.d/wazuh.list
apt-get update -qq

echo "[2/3] Installation de l'agent (manager: ${WAZUH_MANAGER}, groupe: ${AGENT_GROUP})"
WAZUH_MANAGER="${WAZUH_MANAGER}" WAZUH_AGENT_NAME="${AGENT_NAME}" WAZUH_AGENT_GROUP="${AGENT_GROUP}" \
  apt-get install -y -qq wazuh-agent

echo "[3/3] Démarrage du service"
systemctl daemon-reload
systemctl enable --now wazuh-agent

# Geler la version de l'agent (éviter une maj auto incompatible avec le manager)
apt-mark hold wazuh-agent >/dev/null

sleep 3
systemctl is-active --quiet wazuh-agent \
  && echo "[OK] Agent '${AGENT_NAME}' démarré → vérifier son statut 'Active' dans le dashboard." \
  || { echo "[ERREUR] Agent KO → journalctl -u wazuh-agent -n 30"; exit 1; }
