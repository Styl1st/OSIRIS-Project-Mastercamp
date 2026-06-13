#!/usr/bin/env bash
# =============================================================================
# 02-install-wazuh-server.sh — Installation Wazuh 4.14 all-in-one (Phase 1)
# Installe : Wazuh manager + indexer + dashboard sur cette machine.
# Usage : sudo bash 02-install-wazuh-server.sh
# Durée : ~10-15 min
# =============================================================================
set -euo pipefail

WAZUH_VERSION="4.14"
INSTALL_OPTS="-a"   # all-in-one. Ajouter " -i" si RAM < 8 Go (ignore les checks).

[[ $EUID -eq 0 ]] || { echo "[ERREUR] Lancer avec sudo." >&2; exit 1; }

RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
if [[ ${RAM_GB} -le 7 ]]; then
  echo "[ATTENTION] ${RAM_GB} Go RAM détectés (<8). Ajout de -i (ignore hardware checks)."
  INSTALL_OPTS="${INSTALL_OPTS} -i"
fi

cd /root
echo "[1/3] Téléchargement de l'assistant d'installation Wazuh ${WAZUH_VERSION}"
curl -sO "https://packages.wazuh.com/${WAZUH_VERSION}/wazuh-install.sh"

echo "[2/3] Installation all-in-one (manager + indexer + dashboard)…"
# "$@" transmet les options passées au script (ex: -o pour écraser une install existante).
bash ./wazuh-install.sh ${INSTALL_OPTS} "$@"

echo "[3/3] Extraction des identifiants"
echo "============================================================"
echo " IDENTIFIANTS (à conserver en lieu sûr, JAMAIS dans le git) :"
echo "============================================================"
tar -O -xvf /root/wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt 2>/dev/null | grep -A1 "'admin'" || true
echo ""
echo "Tous les mots de passe :"
echo "  sudo tar -O -xvf /root/wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt"
echo ""
IP=$(hostname -I | awk '{print $1}')
echo "=== Installation terminée ==="
echo "Dashboard : https://${IP}  (user: admin)"
echo "Étape suivante : sudo bash 03-post-install-check.sh"
