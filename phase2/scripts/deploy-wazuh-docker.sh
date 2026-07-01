#!/usr/bin/env bash
# =============================================================================
# deploy-wazuh-docker.sh — Deploiement Wazuh multi-noeuds en conteneurs (Phase 2)
# Lance 3 noeuds dedies : wazuh.manager + wazuh.indexer + wazuh.dashboard.
# A lancer sur une machine avec Docker (VM Ubuntu, ou hote via Docker Desktop/WSL).
#
# Usage : sudo bash deploy-wazuh-docker.sh
#   Options (variables d'environnement) :
#     WAZUH_TAG=v4.14.5              version du deploiement Docker Wazuh
#     DEPLOY_DIR=$HOME/wazuh-docker  ou cloner le depot
# =============================================================================
set -euo pipefail

WAZUH_TAG="${WAZUH_TAG:-v4.14.5}"
DEPLOY_DIR="${DEPLOY_DIR:-$HOME/wazuh-docker}"
REPO="https://github.com/wazuh/wazuh-docker.git"

echo "=== Deploiement Wazuh multi-noeuds (Docker) — ${WAZUH_TAG} ==="

# --- 1. Verifier Docker ---
command -v docker >/dev/null 2>&1 || {
  echo "[ERREUR] Docker n'est pas installe." >&2
  echo "         Ubuntu : https://docs.docker.com/engine/install/ubuntu/" >&2
  exit 1
}
docker compose version >/dev/null 2>&1 || {
  echo "[ERREUR] Le plugin 'docker compose' est manquant." >&2
  exit 1
}

# --- 2. vm.max_map_count (requis par l'indexer / OpenSearch) ---
current="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
if (( current < 262144 )); then
  echo "[1/4] Reglage vm.max_map_count=262144 (indexer)"
  sysctl -w vm.max_map_count=262144
  if ! grep -q '^vm.max_map_count' /etc/sysctl.conf 2>/dev/null; then
    echo 'vm.max_map_count=262144' >> /etc/sysctl.conf   # persistant apres reboot
  fi
else
  echo "[1/4] vm.max_map_count deja OK (${current})"
fi

# --- 3. Recuperer le deploiement Docker officiel ---
if [[ -d "${DEPLOY_DIR}/single-node" ]]; then
  echo "[2/4] Depot deja present : ${DEPLOY_DIR}"
else
  echo "[2/4] Clonage de wazuh-docker (${WAZUH_TAG})"
  if ! git clone "${REPO}" -b "${WAZUH_TAG}" --depth=1 "${DEPLOY_DIR}"; then
    echo "[ERREUR] Impossible de cloner le tag ${WAZUH_TAG}." >&2
    echo "         Versions disponibles : https://github.com/wazuh/wazuh-docker/tags" >&2
    echo "         Puis relance : WAZUH_TAG=<tag> sudo bash $0" >&2
    exit 1
  fi
fi
cd "${DEPLOY_DIR}/single-node"

# --- 4. Certificats + demarrage ---
echo "[3/4] Generation des certificats (manager + indexer + dashboard)"
docker compose -f generate-indexer-certs.yml run --rm generator

echo "[4/4] Demarrage des 3 noeuds"
docker compose up -d

echo ""
echo "============================================================"
docker compose ps
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo "============================================================"
echo " Dashboard : https://${IP:-<IP-de-cette-machine>}   (user: admin)"
echo " /!\\ Change le mot de passe par defaut (defini dans docker-compose.yml)."
echo " L'indexer met ~1-2 min a etre pret."
echo "   Suivi : docker compose logs -f wazuh.manager"
echo " Agents : pointer WAZUH_MANAGER vers ${IP:-<IP-de-cette-machine>}"
echo "============================================================"
