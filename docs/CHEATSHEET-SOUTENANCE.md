# Aide-mémoire soutenance — commandes prêtes à copier-coller

Chaque phase est **autonome** : **▶️ Démarrer · 💥 Attaquer · 👁️ Vérifier**. L'icône indique **où taper** : 🟦 serveur .134 · 🟥 Kali · 🟩 srv-linux · 🟪 pfSense.

## Carte de l'environnement

| Machine | IP | Rôle |
|---|---|---|
| 🟦 Serveur Wazuh Phase 1 (all-in-one) | `192.168.195.134` | SIEM Phase 1 |
| 🟥 Kali | `192.168.195.130` | Attaquant + Docker (Phases 2 & 3) |
| 🟩 srv-linux (Ubuntu) | `192.168.195.131` | Agent surveillé / cible |
| 🟪 pfSense | `192.168.195.136` | Firewall |

## Préparation (UNE fois, au tout début)

```bash
# 🟥 Kali — docker sans sudo + comptes/listes pour les attaques SSH
newgrp docker
sudo useradd -m victime 2>/dev/null; echo 'victime:password123' | sudo chpasswd
printf 'x1\nx2\nx3\nx4\nx5\nx6\nx7\nx8\nx9\npassword123\n' > /tmp/wordlist.txt
printf 'w1\nw2\nw3\nw4\nw5\nw6\nw7\nw8\nw9\nw10\n' > /tmp/wl.txt
```

> **Astuce fiabilité (optionnel, 🟦 .134) :** pour un démarrage rapide du manager, désactive la détection de vulnérabilités (inutile en Phase 1, c'est elle qui le ralentit) :
> ```bash
> sudo sed -i '/<vulnerability-detection>/,/<\/vulnerability-detection>/ s|<enabled>yes</enabled>|<enabled>no</enabled>|' /var/ossec/etc/ossec.conf
> ```

### 🧹 Nettoyage des agents + nom stable (UNE fois — pour zéro doublon en démo)

**a) Supprimer les agents fantômes** (entrées `Disconnected` ou au mauvais nom `ubuntu-VMware...`) — lister puis retirer, sur **chaque** manager :
```bash
# 🟦 .134 — lister, repérer les IDs fantômes, les supprimer
sudo /var/ossec/bin/agent_control -ls
sudo /var/ossec/bin/manage_agents -r <ID>            # ex. ancien srv-linux + ubuntu-VMware...
```
```bash
# 🟥 Kali — pareil dans le conteneur
docker exec single-node-wazuh.manager-1 /var/ossec/bin/agent_control -ls
docker exec single-node-wazuh.manager-1 sh -c 'printf "y\n" | /var/ossec/bin/manage_agents -r <ID>'
```

**b) Activer le remplacement forcé** (le re-pointage reconnecte la même entrée au lieu de dupliquer) :
```bash
# 🟦 .134
sudo sed -i 's|<after_registration_time>[^<]*</after_registration_time>|<after_registration_time>0</after_registration_time>|' /var/ossec/etc/ossec.conf
sudo /var/ossec/bin/wazuh-control restart
```
```bash
# 🟥 Kali
docker exec single-node-wazuh.manager-1 sed -i 's|<after_registration_time>[^<]*</after_registration_time>|<after_registration_time>0</after_registration_time>|' /var/ossec/etc/ossec.conf
cd ~/wazuh-docker/single-node && docker compose restart wazuh.manager
```

Après ça, chaque re-pointage (toujours avec `-A srv-linux`) garde **un seul** `srv-linux` Active, sans fantôme.

### 🔗 Intégrations persistantes (UNE fois — sinon perdues au `down/up`)

Les intégrations vivent dans `ossec.conf`, **réécrit à chaque recréation** du conteneur. Pour qu'elles survivent, on les met dans le fichier **source** `wazuh_manager.conf` (remplace les `<...>` par tes valeurs) :
```bash
# 🟥 Kali
cat >> ~/wazuh-docker/single-node/config/wazuh_cluster/wazuh_manager.conf <<'EOF'
<ossec_config>
  <integration>
    <name>custom-discord</name>
    <hook_url><TON_URL_WEBHOOK_SANS_/slack></hook_url>
    <level>12</level>
    <alert_format>json</alert_format>
  </integration>
  <integration>
    <name>virustotal</name>
    <api_key><TA_CLE_VT_SUR_UNE_LIGNE></api_key>
    <group>syscheck</group>
    <alert_format>json</alert_format>
  </integration>
  <active-response>
    <command>firewall-drop</command>
    <location>local</location>
    <rules_id>5712,5720,5763</rules_id>
    <timeout>120</timeout>
  </active-response>
</ossec_config>
EOF
docker compose down && docker compose up -d
```
Le script `custom-discord` (dans un volume) persiste déjà. Après ça, les 3 fonctionnalités marchent direct à chaque démarrage.

---

# PHASE 1 — Déploiement minimal (🟦 serveur `.134`)

## ▶️ Démarrer
1. **Allumer les VMs** : 🟦 wazuh-server (.134), 🟩 srv-linux (.131), 🟪 pfSense (.136).
2. **🟩 srv-linux → pointer vers le manager .134** (nom fixe `-A srv-linux`) **:**
```bash
sudo sed -i 's|<address>[^<]*</address>|<address>192.168.195.134</address>|' /var/ossec/etc/ossec.conf
sudo /var/ossec/bin/agent-auth -m 192.168.195.134 -A srv-linux
sudo systemctl restart wazuh-agent
```
3. **🟦 .134 → démarrer les services Wazuh** (le manager met 1-3 min, c'est normal) :
```bash
sudo rm -rf /var/ossec/var/start-script-lock
sudo systemctl start wazuh-indexer
sudo /var/ossec/bin/wazuh-control restart
sudo systemctl start filebeat wazuh-dashboard
```
4. **Vérifier :**
```bash
sudo /var/ossec/bin/wazuh-control status         # démons "is running"
sudo /var/ossec/bin/agent_control -ls            # srv-linux Active
```
Dashboard prêt après ~1-2 min : `https://192.168.195.134`

## 💥 Attaquer
```bash
# 🟩 srv-linux — FIM (fichier surveillé) -> règle 550
echo "# demo $(date)" | sudo tee -a /etc/hosts

# 🟩 srv-linux — attaque web -> règles 31101 / 31103 / 31106
curl -s "http://localhost/page-inexistante" -o /dev/null
curl -s "http://localhost/?id=1+union+select+1,2,3--" -o /dev/null
curl -s "http://localhost/?q=<script>alert(1)</script>" -o /dev/null

# 🟩 srv-linux — switch Cisco simulé -> règle 4724
logger -n 192.168.195.134 -P 514 -d -t "SW-CORE-01" "%SEC_LOGIN-4-LOGIN_FAILED: Login failed [user: admin] [Source: 192.168.1.50] [localport: 22] [Reason: Login Authentication Failed]"
```
```
# 🟪 pfSense -> règle 2501 : saisir un MAUVAIS mot de passe sur la page de login du GUI pfSense
```

## 👁️ Vérifier
- Dashboard `.134` → **Threat Hunting** → filtres : `rule.id: 550` · `rule.groups: web` · `rule.id: 2501` · `rule.id: 4724`
- Nettoyage : `sudo sed -i '/# demo/d' /etc/hosts`

---

# PHASE 2 — Architecture distribuée (🟥 Kali, stack `single-node`)

## ▶️ Démarrer
1. **Allumer** 🟥 Kali (et 🟩 srv-linux si éteint).
2. **🟩 srv-linux → pointer vers le manager Kali (.130)** (nom fixe `-A srv-linux`) **:**
```bash
sudo sed -i 's|<address>[^<]*</address>|<address>192.168.195.130</address>|' /var/ossec/etc/ossec.conf
sudo /var/ossec/bin/agent-auth -m 192.168.195.130 -A srv-linux
sudo systemctl restart wazuh-agent
```
3. **🟥 Kali → démarrer la stack :**
```bash
newgrp docker
cd ~/wazuh-docker/single-node && docker compose up -d
docker compose ps                                                 # attendre "Up" (~2-3 min)
docker exec single-node-wazuh.manager-1 /var/ossec/bin/agent_control -ls   # agents Active
```
Dashboard : `https://192.168.195.130`

## 💥 Attaquer & 👁️ Vérifier

### 2.1 — Brute force SSH (détection)
```bash
# 💥 🟥 Kali — QUE des mauvais mots de passe -> détection brute force (règle 5763)
hydra -t 4 -l victime -P /tmp/wl.txt ssh://127.0.0.1
# 👁️ 🟥 Kali
docker exec single-node-wazuh.manager-1 grep "brute force" /var/ossec/logs/alerts/alerts.log | tail
```

### 2.2 — Corrélation « brute force → compromission » (+ Discord)
```bash
# 💥 🟥 Kali — mauvais PUIS bon mot de passe -> règle 100210 (niveau 14)
hydra -t 1 -l victime -P /tmp/wordlist.txt ssh://127.0.0.1
# 👁️ 🟥 Kali
docker exec single-node-wazuh.manager-1 grep "100210" /var/ossec/logs/alerts/alerts.log | grep -i compromission
docker exec single-node-wazuh.manager-1 tail -n 5 /var/ossec/logs/integrations.log
```
→ **Discord** : message « compromission probable » · Dashboard → *Threat Hunting* (`rule.id: 100210`)

### 2.3 — Échecs d'authentification / sudo
```bash
# 💥 🟩 srv-linux (ou 🟥 Kali) — plusieurs sudo échoués -> règles d'authentification
for i in 1 2 3 4 5; do sudo -k; echo wrongpass | sudo -S true 2>/dev/null; done
# 👁️ 🟥 Kali
docker exec single-node-wazuh.manager-1 grep -iE "authentication failure|failed" /var/ossec/logs/alerts/alerts.log | tail
```

### 2.4 — Détection de vulnérabilités
Dashboard `https://192.168.195.130` → **Vulnerability Detection** → onglet *Inventory* (CVE par agent).

### 2.5 — Rétention des logs (cycle de vie)
```bash
# 👁️ 🟥 Kali — la politique de rétention 90 jours (ISM)
curl -k -u admin:SecretPassword "https://localhost:9200/_plugins/_ism/policies/wazuh-alerts-retention?pretty" | grep -E "policy_id|min_index_age"
```
Dashboard → **Indexer management → State management policies**.

### 2.6 — Alerting temps réel
Toute alerte de niveau ≥ 12 (ex. la corrélation 2.2) déclenche automatiquement une notif **Discord**.

---

# PHASE 3 — Fonctions avancées (🟥 Kali)

## ▶️ Démarrer
Les démos 3.1 à 3.4 tournent sur la **même stack que la Phase 2** (`single-node` sur Kali). **Si elle tourne déjà, rien à faire.** Sinon :
```bash
# 🟥 Kali
cd ~/wazuh-docker/single-node && docker compose up -d
```
(La démo **3.5 Cluster** a son propre démarrage, plus bas.)

## 3.1 — Threat Intelligence VirusTotal
```bash
# 💥 🟩 srv-linux — déposer un fichier malveillant test (nom NEUF à chaque fois)
echo 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' | sudo tee /root/vt-test/eicar-demo.com
```
```bash
# 👁️ 🟥 Kali -> Rule 87105 : X engines detected + Discord
docker exec single-node-wazuh.manager-1 grep -i virustotal /var/ossec/logs/alerts/alerts.log | tail
```

## 3.2 — Réponse automatique (Active Response)
```bash
# 💥 🟥 Kali — brute force SSH sur srv-linux, puis reconnexion (doit être BLOQUÉE)
hydra -t 4 -l ubuntu -P /tmp/wl.txt ssh://192.168.195.131 && ssh -o ConnectTimeout=5 ubuntu@192.168.195.131
```
```bash
# 👁️ 🟩 srv-linux — blocage automatique de l'IP de Kali
sudo tail -n 20 /var/ossec/logs/active-responses.log
sudo iptables -L -n | grep 192.168.195.130      # règle DROP pendant ~120 s
```

## 3.3 — IDS Suricata
```bash
# ▶️ 🟩 srv-linux — s'assurer que Suricata tourne
sudo systemctl start suricata
# 💥 🟩 srv-linux — test IDS standard
curl http://testmynids.org/uid/index.html
```
```bash
# 👁️ 🟩 srv-linux
sudo grep '"event_type":"alert"' /var/log/suricata/eve.json | tail -2
# 👁️ 🟥 Kali -> Rule 86601 : Suricata Alert
docker exec single-node-wazuh.manager-1 grep -i suricata /var/ossec/logs/alerts/alerts.log | tail
```

## 3.4 — MITRE ATT&CK
Dashboard `https://192.168.195.130` → menu ☰ → **MITRE ATT&CK** → onglet **Dashboard** (techniques : Brute Force, SSH, Valid Accounts…)

## 3.5 — Cluster multi-nœuds + Load balancing (stack `multi-node`)
```bash
# ▶️ 🟥 Kali — basculer du single-node vers le cluster
cd ~/wazuh-docker/single-node && docker compose down
cd ~/wazuh-docker/multi-node
sudo sysctl -w vm.max_map_count=262144
docker compose up -d
docker compose ps                # 7 conteneurs Up (~2-3 min)
```
```bash
# 👁️ 🟥 Kali — cluster de 2 managers
docker exec multi-node-wazuh.master-1 /var/ossec/bin/cluster_control -l
# 👁️ 🟥 Kali — cluster de 3 indexers (santé green)
curl -k -u admin:SecretPassword "https://localhost:9200/_cluster/health?pretty" | grep -E '"status"|"number_of_nodes"'
```
Le conteneur **nginx** = le load balancer (port agents 1514).

---

# 🔌 Éteindre (à la toute fin)

```bash
# 🟥 Kali — arrêter la stack Docker en cours (config préservée dans les volumes)
cd ~/wazuh-docker/single-node && docker compose down     # (ou multi-node)
```
Puis éteindre chaque VM : `sudo poweroff` (ou clic droit → Éteindre dans VMware).

---

## Ordre conseillé

1. **Préparation** (une fois).
2. **Phase 1** → démarrer .134 (srv-linux vers .134) → FIM / web / firewall / switch.
3. **Phase 2** → démarrer Kali single-node (srv-linux vers .130) → corrélation + Discord + vulnérabilités.
4. **Phase 3** (3.1→3.4) sur la même stack → VirusTotal → Active Response → IDS → MITRE.
5. **Phase 3.5** → basculer sur multi-node → cluster + load balancing.
6. **Éteindre**.

> Règle d'or : **teste chaque commande une fois avant** le public, et garde un terminal `tail -f alerts.log` visible. Les IPs peuvent changer si tu redémarres des VMs → réadapte-les.
