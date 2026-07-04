# Guide de démonstration — Phase 3 (fonctions avancées)

Ce guide montre comment provoquer et observer les capacités **avancées** de la Phase 3 : threat intelligence, réponse automatique, MITRE ATT&CK, etc. Il s'appuie sur la stack multi-nœuds Docker de la Phase 2 (conteneurs `wazuh.manager` / `wazuh.indexer` / `wazuh.dashboard` sur l'hôte Kali).

> **Document vivant** — enrichi au fur et à mesure qu'on valide chaque fonctionnalité.

---

## 0. Prérequis

```bash
newgrp docker
cd ~/wazuh-docker/single-node && docker compose ps   # les 3 conteneurs = Up
```

Dashboard : `https://<IP-Kali>`. Le conteneur manager est `single-node-wazuh.manager-1`.

---

## 1. Threat Intelligence — VirusTotal

**Ce qu'on démontre :** le SIEM **enrichit ses détections** avec une source de threat intelligence externe — tout fichier suspect qui apparaît sur une machine surveillée est croisé automatiquement avec **70+ moteurs antivirus** via l'API VirusTotal.

**Comment ça marche :**
1. Le **FIM** de l'agent surveille un dossier en temps réel.
2. Quand un fichier y est créé/modifié, l'agent calcule son **hash** et remonte une alerte.
3. L'**intégration VirusTotal** du manager envoie ce hash à l'API VT ; si le fichier est connu comme malveillant, une alerte **87105** est levée (et notifiée sur Discord si niveau ≥ seuil).

**Config — FIM sur l'agent** (hôte Kali, `/var/ossec/etc/ossec.conf`) :

```xml
<ossec_config>
  <syscheck>
    <alert_new_files>yes</alert_new_files>
    <directories realtime="yes" check_all="yes">/root/vt-test</directories>
  </syscheck>
</ossec_config>
```

**Config — intégration VT sur le manager** (dans le conteneur, `/var/ossec/etc/ossec.conf`) :

```xml
<ossec_config>
  <integration>
    <name>virustotal</name>
    <api_key>VOTRE_CLE_VT_64_CARACTERES</api_key>   <!-- SECRET, hors git -->
    <group>syscheck</group>
    <alert_format>json</alert_format>
  </integration>
</ossec_config>
```

**Test (attaque simulée) — fichier EICAR** (chaîne de test antivirus standard, inoffensive) :

```bash
echo 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' | sudo tee /root/vt-test/eicar.com
```

**Où vérifier :**
- **Discord** (webhook Phase 2) : message `Rule 87105 - VirusTotal: Alert - .../eicar.com - 61 engines detected this file`.
- Dashboard → *Threat Hunting* → `rule.id: 87105`.
- Terminal : `docker exec single-node-wazuh.manager-1 grep -i virustotal /var/ossec/logs/alerts/alerts.log | tail`.

**Résultat obtenu :** EICAR détecté par **61 moteurs** → alerte niveau 12 → notification Discord temps réel. La chaîne complète détection → threat intel → alerte fonctionne.

**Pièges rencontrés (à connaître) :**
- La **clé API** doit être sur **une seule ligne** (un retour à la ligne collé dedans → erreur `403 Check credentials`, règle 87102). Astuce : `VT_KEY=$(echo -n "..." | tr -d '[:space:]')`.
- Chaque fichier n'est signalé qu'**une fois** par le FIM : pour re-tester, créer un **nouveau** fichier.
- Le plan gratuit VT est **limité en débit** (~4 requêtes/min) — suffisant pour la démo.

**À dire :** *« Dès qu'un fichier suspect apparaît sur une machine, le SIEM le soumet automatiquement à VirusTotal. Ici le fichier de test est reconnu comme malveillant par 61 antivirus, et l'équipe est alertée en temps réel. »*

---

## 2. Réponse automatique (Active Response)

**Ce qu'on démontre :** le SIEM ne fait pas que détecter — il **réagit automatiquement**. Ici, dès qu'une attaque par force brute SSH est repérée, l'IP de l'attaquant est **bloquée automatiquement** sur la machine ciblée (règle iptables), puis débloquée après un délai.

**Topologie (sans nouvelle VM) :** `srv-linux` (192.168.195.131) = cible surveillée (agent), Kali (192.168.195.130) = attaquant. `srv-linux` est rattaché au manager Docker de Kali.

**Config — sur le manager** (`/var/ossec/etc/ossec.conf`) :

```xml
<ossec_config>
  <active-response>
    <command>firewall-drop</command>       <!-- ajoute une regle iptables DROP sur l'IP source -->
    <location>local</location>             <!-- s'execute sur l'agent qui a detecte l'attaque -->
    <rules_id>5712,5720,5763</rules_id>    <!-- regles de brute force SSH -->
    <timeout>120</timeout>                 <!-- deblocage auto apres 120 s -->
  </active-response>
</ossec_config>
```

**Rattacher `srv-linux` au manager de Kali** (si besoin) — sur `srv-linux` :

```bash
sudo systemctl enable --now ssh
KALI_IP="192.168.195.130"
sudo sed -i "s|<address>[^<]*</address>|<address>${KALI_IP}</address>|" /var/ossec/etc/ossec.conf
sudo /var/ossec/bin/agent-auth -m ${KALI_IP}
sudo systemctl restart wazuh-agent
```

**Test (attaque réelle depuis Kali)** — brute force SSH sur la cible :

```bash
printf 'w1\nw2\nw3\nw4\nw5\nw6\nw7\nw8\nw9\nw10\n' > /tmp/wl.txt
hydra -t 4 -l ubuntu -P /tmp/wl.txt ssh://192.168.195.131
```

**Où vérifier (sur `srv-linux`) :**
- `sudo tail -f /var/ossec/logs/active-responses.log` → lignes `firewall-drop ... "command":"add" ... srcip 192.168.195.130`, puis `"command":"delete"` après 120 s.
- **Pendant** les 120 s : `sudo iptables -L -n | grep 192.168.195.130` → règle `DROP` (ou `sudo nft list ruleset | grep ...` sur Ubuntu récent).
- Depuis Kali (pendant le blocage) : `ssh ubuntu@192.168.195.131` → **timeout**.

**Résultat obtenu :** brute force détecté (rule 5763) → IP de Kali bloquée automatiquement → déblocage temporisé après 120 s. La boucle **détection → réponse** est fermée sans intervention humaine.

**À dire :** *« Le SIEM passe de la détection à l'action : une attaque par force brute est non seulement repérée, mais l'attaquant est immédiatement isolé du système, automatiquement, puis réintégré après un délai — c'est la base d'un SOAR (réponse orchestrée). »*

---

## 3. MITRE ATT&CK

**Ce qu'on démontre :** le SIEM replace chaque détection sur le **référentiel MITRE ATT&CK** (tactiques → techniques), le langage standard des analystes SOC. C'est **natif** dans Wazuh : chaque règle porte des tags `mitre` (ex. règle 5763 → `T1110 Brute Force`), et le dashboard agrège tout automatiquement.

**Où le voir :** Dashboard → menu ☰ → module **MITRE ATT&CK** → onglet **Dashboard** (données réelles) et **Framework/Intelligence** (matrice de référence).

**Résultat obtenu (à partir de nos attaques) :**
- **Techniques** : *Brute Force* / *Password Guessing* (T1110 — attaques hydra), *SSH* (T1021.004 — mouvement latéral), *Valid Accounts* (T1078), *Sudo and Sudo Caching* (T1548.003 — élévation de privilèges).
- **Tactiques** : Credential Access (dominante), Privilege Escalation, Lateral Movement, Defense Evasion, Persistence, Initial Access.
- Vue **ventilée par agent** (`kali`, `srv-linux`).

**Enrichir (rôle Détection) :** ajouter des `<mitre><id>...</id></mitre>` aux règles custom de `rules/local_rules.xml` (la règle 100210 a déjà T1110 ; ex. T1046 pour un scan réseau, T1059 pour l'exécution de commandes).

**À dire :** *« Chaque attaque est automatiquement cartographiée sur MITRE ATT&CK. Un analyste voit d'un coup d'œil quelles tactiques et techniques ont été employées — ici principalement de l'accès aux identifiants via force brute — ce qui permet de prioriser la réponse selon un standard reconnu mondialement. »*

---

## 4. Cluster & load balancing / autres intégrations

_À compléter (IDS Suricata, cloud, Active Directory…)._

---

## Aide-mémoire

```bash
docker exec single-node-wazuh.manager-1 grep -i virustotal /var/ossec/logs/alerts/alerts.log | tail
docker exec single-node-wazuh.manager-1 tail -n 20 /var/ossec/logs/integrations.log
```
