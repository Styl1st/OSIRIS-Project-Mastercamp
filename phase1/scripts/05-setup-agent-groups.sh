#!/usr/bin/env bash
# =============================================================================
# 05-setup-agent-groups.sh — Groupes d'agents + configuration centralisee
# A lancer sur le SERVEUR Wazuh (manager), apres 02 et 03.
#
# Ce script :
#   1. cree les groupes d'agents ("linux", "windows") sur le manager ;
#   2. deploie la conf partagee configs/shared-agent-<groupe>.conf
#      dans /var/ossec/etc/shared/<groupe>/agent.conf (FIM, collecte de logs...) ;
#   3. laisse le manager distribuer la conf aux agents.
#
# Sans ces groupes, l'enrolement d'un agent echoue avec :
#   "ERROR: Invalid group: linux. Unable to add agent (from manager)"
#
# Idempotent : relancable sans risque (ne recree pas un groupe deja present).
# Usage : sudo bash 05-setup-agent-groups.sh
# =============================================================================
set -euo pipefail

# --- Groupes a creer (doivent correspondre a configs/shared-agent-<groupe>.conf) ---
GROUPS=(linux windows)

OSSEC_BIN="/var/ossec/bin"
SHARED_DIR="/var/ossec/etc/shared"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../configs"

[[ $EUID -eq 0 ]] || { echo "[ERREUR] Lancer avec sudo." >&2; exit 1; }

# Garde-fou : ce script ne tourne que sur le manager, pas sur un agent.
[[ -x "${OSSEC_BIN}/agent_groups" ]] || {
  echo "[ERREUR] ${OSSEC_BIN}/agent_groups introuvable." >&2
  echo "         A lancer sur le SERVEUR Wazuh (manager), pas sur une machine agent." >&2
  exit 1
}

# --- 1. Le manager doit etre pret (agent_groups renvoie l'erreur 1017 sinon) ---
# NB : wazuh-modulesd peut mettre 30-60 s a demarrer (telechargement des flux CVE
#      au 1er lancement) — on attend donc activement, jusqu'a 90 s.
echo "[1/4] Verification de l'etat du manager"
wait_modulesd() {
  local tries=18   # 18 x 5 s = 90 s max
  local i
  for ((i=1; i<=tries; i++)); do
    "${OSSEC_BIN}/wazuh-control" status | grep -q "wazuh-modulesd is running" && return 0
    sleep 5
  done
  return 1
}
if ! "${OSSEC_BIN}/wazuh-control" status | grep -q "wazuh-modulesd is running"; then
  echo "      wazuh-modulesd pas encore pret -> redemarrage du manager et attente (jusqu'a 90 s)..."
  systemctl restart wazuh-manager
fi
if wait_modulesd; then
  echo "      [OK] manager pret (wazuh-modulesd running)."
else
  echo "[ERREUR] wazuh-modulesd ne demarre pas apres 90 s." >&2
  echo "         Voir : sudo tail -n 50 /var/ossec/logs/ossec.log" >&2
  exit 1
fi

# --- 2. Creation des groupes (idempotent) ---
echo "[2/4] Creation des groupes"
existing="$("${OSSEC_BIN}/agent_groups" -l 2>/dev/null || true)"
for g in "${GROUPS[@]}"; do
  if echo "${existing}" | grep -qw "${g}"; then
    echo "      [SKIP] groupe '${g}' deja present"
  else
    "${OSSEC_BIN}/agent_groups" -a -g "${g}" -q && echo "      [OK]   groupe '${g}' cree"
  fi
done

# --- 3. Deploiement des configs partagees ---
echo "[3/4] Deploiement des configurations partagees (agent.conf)"
for g in "${GROUPS[@]}"; do
  src="${CONFIG_DIR}/shared-agent-${g}.conf"
  dst_dir="${SHARED_DIR}/${g}"
  dst="${dst_dir}/agent.conf"
  if [[ -f "${src}" ]]; then
    mkdir -p "${dst_dir}"
    install -o wazuh -g wazuh -m 0660 "${src}" "${dst}"
    chown wazuh:wazuh "${dst_dir}"
    echo "      [OK]   ${src##*/} -> ${dst}"
  else
    echo "      [INFO] pas de conf pour '${g}' (${src} absent) — ignore"
  fi
done

# --- 4. Application de la conf ---
# Pas besoin de redemarrer le manager : il detecte les changements dans
# /var/ossec/etc/shared/ et pousse automatiquement la conf aux agents du groupe.
echo "[4/4] Configurations en place (distribution automatique aux agents du groupe)."

IP="$(hostname -I | awk '{print $1}')"
echo ""
echo "============================================================"
echo " Groupes disponibles :"
"${OSSEC_BIN}/agent_groups" -l | sed 's/^/   /'
echo "============================================================"
echo ""
echo "Etape suivante — installer un agent (sur CHAQUE machine cliente) :"
echo "  Linux   : sudo WAZUH_MANAGER=${IP} AGENT_NAME=srv-linux AGENT_GROUP=linux bash agents/linux/install-agent.sh"
echo "  Windows : .\\install-agent.ps1 -Manager ${IP} -AgentGroup windows   (PowerShell admin)"
echo ""
echo "Verifier l'enrolement (sur le serveur) :"
echo "  sudo ${OSSEC_BIN}/agent_control -ls"
