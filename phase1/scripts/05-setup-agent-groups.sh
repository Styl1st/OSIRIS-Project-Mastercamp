#!/usr/bin/env bash
# =============================================================================
# 05-setup-agent-groups.sh — Groupes d'agents + configuration centralisee
# A lancer sur le SERVEUR Wazuh (manager), apres 02 et 03.
#
# Ce script :
#   1. cree les groupes d'agents ("linux", "windows") s'ils n'existent pas ;
#   2. deploie la conf partagee configs/shared-agent-<groupe>.conf
#      dans /var/ossec/etc/shared/<groupe>/agent.conf (FIM, collecte de logs...) ;
#   3. laisse le manager distribuer la conf aux agents.
#
# Sans ces groupes, l'enrolement d'un agent echoue avec :
#   "ERROR: Invalid group: linux. Unable to add agent (from manager)"
#
# NB : un groupe = un dossier sous /var/ossec/etc/shared/. On n'attend que le
#      manager soit pret QUE si l'on doit reellement creer un groupe (la creation
#      passe par agent_groups, qui exige que les demons soient prets — erreur 1017
#      sinon, et modulesd peut mettre 1-3 min a demarrer au 1er lancement).
#
# Idempotent : relancable sans risque.
# Usage : sudo bash 05-setup-agent-groups.sh
# =============================================================================
set -euo pipefail

# --- Groupes a gerer (doivent correspondre a configs/shared-agent-<groupe>.conf) ---
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

# --- 1. Quels groupes manquent ? (presence du dossier sous shared/) ---
echo "[1/3] Verification des groupes existants"
missing=()
for g in "${GROUPS[@]}"; do
  if [[ -d "${SHARED_DIR}/${g}" ]]; then
    echo "      [SKIP] groupe '${g}' deja present"
  else
    missing+=("${g}")
  fi
done

# --- 2. Creation des groupes manquants (necessite un manager pret) ---
if (( ${#missing[@]} > 0 )); then
  echo "[2/3] Creation des groupes manquants : ${missing[*]}"
  echo "      Attente que le manager reponde (modulesd peut mettre 1-3 min au 1er demarrage)..."
  ready=0
  for ((i=1; i<=36; i++)); do          # 36 x 5 s = 180 s max
    if "${OSSEC_BIN}/agent_groups" -l >/dev/null 2>&1; then ready=1; break; fi
    sleep 5
  done
  if (( ready == 0 )); then
    echo "[ERREUR] Le manager ne repond pas apres 180 s." >&2
    echo "         Verifier : sudo ${OSSEC_BIN}/wazuh-control status" >&2
    echo "                    sudo tail -n 50 /var/ossec/logs/ossec.log" >&2
    exit 1
  fi
  for g in "${missing[@]}"; do
    "${OSSEC_BIN}/agent_groups" -a -g "${g}" -q && echo "      [OK]   groupe '${g}' cree"
  done
else
  echo "[2/3] Tous les groupes existent deja — pas d'attente du manager necessaire."
fi

# --- 3. Deploiement des configs partagees (simple copie de fichiers) ---
echo "[3/3] Deploiement des configurations partagees (agent.conf)"
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

IP="$(hostname -I | awk '{print $1}')"
echo ""
echo "============================================================"
echo " Groupes prets : ${GROUPS[*]}"
echo "============================================================"
echo ""
echo "Etape suivante — installer un agent (sur CHAQUE machine cliente) :"
echo "  Linux   : sudo WAZUH_MANAGER=${IP} AGENT_NAME=srv-linux AGENT_GROUP=linux bash agents/linux/install-agent.sh"
echo "  Windows : .\\install-agent.ps1 -Manager ${IP} -AgentGroup windows   (PowerShell admin)"
echo ""
echo "Verifier l'enrolement (sur le serveur) :"
echo "  sudo ${OSSEC_BIN}/agent_control -ls"
