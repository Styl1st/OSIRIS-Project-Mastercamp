#!/usr/bin/env bash
# =============================================================================
# 05-setup-agent-groups.sh — Groupes d'agents + configuration centralisée
# À lancer sur le SERVEUR Wazuh (manager), après 02 et 03.
#
# Ce script :
#   1. crée les groupes d'agents ("linux", "windows") sur le manager ;
#   2. déploie la conf partagée configs/shared-agent-<groupe>.conf
#      dans /var/ossec/etc/shared/<groupe>/agent.conf (FIM, collecte de logs…) ;
#   3. recharge le manager.
#
# Sans ces groupes, l'enrôlement d'un agent échoue avec :
#   "ERROR: Invalid group: linux. Unable to add agent (from manager)"
#
# Idempotent : relançable sans risque (ne recrée pas un groupe déjà présent).
# Usage : sudo bash 05-setup-agent-groups.sh
# =============================================================================
set -euo pipefail

# --- Groupes à créer (doivent correspondre à configs/shared-agent-<groupe>.conf) ---
GROUPS=(linux windows)

OSSEC_BIN="/var/ossec/bin"
SHARED_DIR="/var/ossec/etc/shared"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../configs"

[[ $EUID -eq 0 ]] || { echo "[ERREUR] Lancer avec sudo." >&2; exit 1; }

# Garde-fou : ce script ne tourne que sur le manager, pas sur un agent.
[[ -x "${OSSEC_BIN}/agent_groups" ]] || {
  echo "[ERREUR] ${OSSEC_BIN}/agent_groups introuvable." >&2
  echo "         À lancer sur le SERVEUR Wazuh (manager), pas sur une machine agent." >&2
  exit 1
}

# --- 1. Le manager doit être prêt (agent_groups renvoie l'erreur 1017 sinon) ---
echo "[1/4] Vérification de l'état du manager"
if ! "${OSSEC_BIN}/wazuh-control" status | grep -q "wazuh-modulesd is running"; then
  echo "      wazuh-modulesd inactif → redémarrage du manager…"
  systemctl restart wazuh-manager
  sleep 10
fi
"${OSSEC_BIN}/wazuh-control" status | grep -q "wazuh-modulesd is running" || {
  echo "[ERREUR] Le manager n'est pas prêt (wazuh-modulesd en échec)." >&2
  echo "         Voir : sudo tail -n 50 /var/ossec/logs/ossec.log" >&2
  exit 1
}
echo "      [OK] manager prêt."

# --- 2. Création des groupes (idempotent) ---
echo "[2/4] Création des groupes"
existing="$("${OSSEC_BIN}/agent_groups" -l 2>/dev/null || true)"
for g in "${GROUPS[@]}"; do
  if echo "${existing}" | grep -qw "${g}"; then
    echo "      [SKIP] groupe '${g}' déjà présent"
  else
    "${OSSEC_BIN}/agent_groups" -a -g "${g}" -q && echo "      [OK]   groupe '${g}' créé"
  fi
done

# --- 3. Déploiement des configs partagées ---
echo "[3/4] Déploiement des configurations partagées (agent.conf)"
for g in "${GROUPS[@]}"; do
  src="${CONFIG_DIR}/shared-agent-${g}.conf"
  dst_dir="${SHARED_DIR}/${g}"
  dst="${dst_dir}/agent.conf"
  if [[ -f "${src}" ]]; then
    mkdir -p "${dst_dir}"
    install -o wazuh -g wazuh -m 0660 "${src}" "${dst}"
    chown wazuh:wazuh "${dst_dir}"
    echo "      [OK]   ${src##*/} → ${dst}"
  else
    echo "      [INFO] pas de conf pour '${g}' (${src} absent) — ignoré"
  fi
done

# --- 4. Rechargement du manager pour appliquer la conf ---
echo "[4/4] Redémarrage du manager pour appliquer la configuration…"
systemctl restart wazuh-manager
sleep 5

echo ""
echo "============================================================"
echo " Groupes disponibles :"
"${OSSEC_BIN}/agent_groups" -l | sed 's/^/   /'
echo "============================================================"
echo ""
echo "Étape suivante — installer un agent (sur CHAQUE machine cliente) :"
echo "  Linux   : sudo WAZUH_MANAGER=$(hostname -I | awk '{print $1}') AGENT_NAME=srv-linux AGENT_GROUP=linux bash agents/linux/install-agent.sh"
echo "  Windows : .\\install-agent.ps1 -Manager $(hostname -I | awk '{print $1}') -AgentGroup windows   (PowerShell admin)"
echo ""
echo "Vérifier l'enrôlement (sur le serveur) :"
echo "  sudo ${OSSEC_BIN}/agent_control -ls"
