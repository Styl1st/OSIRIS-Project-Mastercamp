#!/usr/bin/env bash
# =============================================================================
# 03-post-install-check.sh — Vérification du serveur Wazuh all-in-one
# Usage : sudo bash 03-post-install-check.sh
# =============================================================================
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "[ERREUR] Lancer avec sudo." >&2; exit 1; }

PASS=0; FAIL=0
ok()   { echo "  [OK]   $1"; PASS=$((PASS+1)); }
ko()   { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "=== 1. Services ==="
for svc in wazuh-manager wazuh-indexer wazuh-dashboard filebeat; do
  systemctl is-active --quiet "$svc" && ok "$svc actif" || ko "$svc inactif → journalctl -u $svc"
done

echo "=== 2. Ports en écoute ==="
for p in 443 1514 1515 9200 55000; do
  ss -tln "( sport = :$p )" | grep -q LISTEN && ok "port $p/tcp" || ko "port $p/tcp fermé"
done

echo "=== 3. Dashboard HTTPS ==="
CODE=$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 10 https://localhost/)
[[ "$CODE" =~ ^(200|302)$ ]] && ok "dashboard répond (HTTP $CODE)" || ko "dashboard HTTP $CODE"

echo "=== 4. Filebeat → Indexer ==="
filebeat test output 2>/dev/null | grep -q "talk to server... OK" && ok "filebeat → indexer" || ko "filebeat ne joint pas l'indexer"

echo "=== 5. Agents enrôlés ==="
/var/ossec/bin/agent_control -ls 2>/dev/null | tail -n +1 || echo "  (aucun agent pour l'instant — normal au premier lancement)"

echo ""
echo "Résultat : ${PASS} OK / ${FAIL} FAIL"
[[ $FAIL -eq 0 ]] && echo "✅ Serveur Wazuh opérationnel → https://$(hostname -I | awk '{print $1}')" \
  || echo "❌ Corriger les points FAIL ci-dessus (journalctl -u <service> -n 50)"
