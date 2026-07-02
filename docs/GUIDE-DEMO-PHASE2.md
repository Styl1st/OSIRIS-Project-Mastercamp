# Guide de démonstration — Phase 2 (architecture distribuée)

Ce guide montre comment **provoquer et observer** les nouvelles capacités de la Phase 2 : détection de vulnérabilités, **corrélation d'événements**, évaluation de configuration (SCA/ISO 27001), puis alerting et rétention. Il complète le guide Phase 1 (`GUIDE-DEMO-ATTAQUES.md`), qui reste valable.

> **Ce document est vivant** : il s'enrichit au fur et à mesure qu'on valide chaque fonctionnalité de la Phase 2.

---

## 0. Contexte & prérequis

La Phase 2 tourne en **architecture multi-nœuds** : le manager, l'indexer et le dashboard sont **3 conteneurs Docker distincts** (déploiement `wazuh-docker` single-node) sur l'hôte **Kali** (`192.168.195.x`).

Avant toute démo :

```bash
# État des 3 nœuds (dans ~/wazuh-docker/single-node)
sudo docker compose ps                 # wazuh.manager / wazuh.indexer / wazuh.dashboard = Up

# Agents connectés
sudo docker exec single-node-wazuh.manager-1 /var/ossec/bin/agent_control -ls
```

Dashboard : `https://<IP-de-Kali>` (module Threat Hunting pour les alertes).

> Le nom du conteneur manager est `single-node-wazuh.manager-1` (vérifiable avec `sudo docker ps`). On l'utilise dans les commandes ci-dessous.

---

## 1. Détection de vulnérabilités

**Ce qu'on démontre :** le SIEM identifie automatiquement les **CVE** présentes sur les machines surveillées, en croisant l'inventaire logiciel de l'agent avec les flux de vulnérabilités.

**Comment ça marche :** le module `syscollector` de l'agent envoie l'inventaire des paquets → le manager le compare aux bases CVE téléchargées → les vulnérabilités apparaissent dans le dashboard. **C'est automatique** (activé par défaut en 4.x), aucune action d'attaque nécessaire.

**Où vérifier :**
- Dashboard → module **Vulnerability Detection** → onglets *Dashboard* / *Inventory* / *Events*, filtrés sur l'agent.
- État du scanner côté manager :

```bash
sudo docker exec single-node-wazuh.manager-1 grep -i "vulnerability" /var/ossec/logs/ossec.log | tail
```

**Résultat observé :** ex. `CVE-2025-23217` détectée sur le paquet `mitmproxy` de l'agent Kali. (Kali étant riche en outils, beaucoup de CVE remontent — idéal en démo.)

**Pour enrichir la démo :** installer volontairement un paquet ancien/vulnérable sur un agent, attendre le prochain scan d'inventaire, et voir la nouvelle CVE apparaître.

**À dire :** *« Sans lancer d'attaque, le SIEM inventorie les logiciels de chaque machine et signale celles qui présentent des failles connues (CVE), avec leur criticité — c'est la base de la gestion des vulnérabilités. »*

---

## 2. Corrélation d'événements — brute force → compromission

**Ce qu'on démontre :** le cœur de la Phase 2. Une **règle custom** (`100210`, niveau 14) relie **plusieurs événements** en une seule alerte critique : une **connexion réussie survenant juste après une attaque par force brute, depuis la même IP** = compromission probable.

**La règle** (dans `rules/local_rules.xml`, déployée sur le manager) :

```xml
<group name="local,syslog,sshd,correlation,">
  <rule id="100210" level="14" timeframe="300">
    <if_sid>5715</if_sid>                                       <!-- connexion SSH reussie -->
    <if_matched_group>authentication_failures</if_matched_group> <!-- APRES un brute force -->
    <same_source_ip />                                          <!-- ... depuis la meme IP -->
    <description>Connexion SSH reussie APRES une attaque brute force (meme IP) - compromission probable</description>
    <mitre><id>T1110</id></mitre>
  </rule>
</group>
```

> **Astuce importante :** on utilise `if_matched_group authentication_failures` (et non un `if_matched_sid` unique) car Wazuh emploie des règles de brute force **différentes** selon la cible : `5712` pour un utilisateur **inexistant**, `5763` pour un utilisateur **existant**. Le groupe les couvre toutes.

### 2a. Valider la règle (rapide, sans attaque réelle)

```bash
sudo docker exec -it single-node-wazuh.manager-1 /var/ossec/bin/wazuh-logtest
```

Colle **8 fois** (une par une) cette ligne d'échec, même IP `10.0.0.66` :

```
Jul  2 10:00:01 kali sshd[1001]: Failed password for invalid user admin from 10.0.0.66 port 4444 ssh2
```

→ la 8ᵉ déclenche la règle **5712** (brute force). Colle ensuite la connexion réussie, même IP :

```
Jul  2 10:00:20 kali sshd[1010]: Accepted password for root from 10.0.0.66 port 4444 ssh2
```

→ déclenche **`100210` niveau 14** « compromission probable ». Preuve que la corrélation fonctionne.

### 2b. Démo live avec hydra (idéale en soutenance)

**Kali = machine d'attaque.** On lance une vraie attaque par force brute SSH.

**Préparation (une fois), sur la cible** (un agent Linux, ou Kali lui-même) :

```bash
sudo systemctl enable --now ssh                              # activer SSH
sudo useradd -m victime && echo 'victime:password123' | sudo chpasswd   # compte a mot de passe faible
```

**Sur Kali (attaquant)**, une petite liste contenant le bon mot de passe, puis hydra :

```bash
printf 'admin\nroot\n123456\npassword123\n' > /tmp/wordlist.txt
hydra -l victime -P /tmp/wordlist.txt ssh://<IP-de-la-cible>
```

Hydra enchaîne les tentatives → échecs (`5712` brute force), puis trouve `password123` → **connexion réussie** → ta règle **`100210`** s'allume.

**Où voir :**
- Dashboard → *Threat Hunting* → filtre `rule.id: 100210` (et `rule.id: 5712` pour le brute force).
- Terminal :

```bash
sudo docker exec single-node-wazuh.manager-1 grep "100210" /var/ossec/logs/alerts/alerts.log
```

**À dire :** *« Kali mène une vraie attaque par force brute. Le SIEM détecte d'abord la rafale d'échecs, puis — au moment où l'attaquant trouve le mot de passe et se connecte — corrèle les deux événements en une alerte de compromission de niveau 14. Un login réussi isolé est anodin ; corrélé à l'attaque qui précède, il devient critique. »*

---

## 3. Évaluation de configuration (SCA / ISO 27001)

**Ce qu'on démontre :** le SIEM audite la configuration des machines par rapport à des référentiels de durcissement (CIS), ce qui alimente la conformité **ISO 27001**.

**Comment ça marche :** le module `SCA` de l'agent exécute des politiques (ex. `sca_distro_independent_linux.yml`) et remonte un score de conformité (checks *passed / failed*). Automatique.

**Où vérifier :** Dashboard → module **Security Configuration Assessment (SCA)** → sélectionner l'agent → voir les contrôles réussis/échoués et les recommandations.

**À dire :** *« Au-delà de détecter les attaques, le SIEM évalue en continu si les machines respectent les bonnes pratiques de sécurité (référentiel CIS), ce qui documente directement la conformité ISO 27001. »*

---

## 4. Alerting (webhook Discord)

**Ce qu'on démontre :** le SIEM **notifie en temps réel** sur un canal externe (Discord) dès qu'une alerte critique survient — ici, l'alerte de compromission `100210` (niveau 14) déclenchée par l'attaque hydra.

**Pourquoi un webhook et pas l'email :** en conteneur, l'email exige un relais SMTP ; un webhook Discord/Slack est immédiat et visuel.

**Comment ça marche :** une **intégration custom** (`/var/ossec/integrations/custom-discord`) est appelée par `wazuh-integratord` à chaque alerte de niveau ≥ 12, et poste un message formaté dans le salon via son webhook.

**Config côté manager** (`/var/ossec/etc/ossec.conf`) :

```xml
<ossec_config>
  <integration>
    <name>custom-discord</name>
    <hook_url>https://discord.com/api/webhooks/XXXX/YYYY</hook_url>  <!-- URL SECRETE, hors git -->
    <level>12</level>
    <alert_format>json</alert_format>
  </integration>
</ossec_config>
```

Le script `custom-discord` (Python) lit l'alerte JSON et poste `{"content": "..."}` sur le webhook. **Deux pièges rencontrés** (à connaître) :

- Le **Python embarqué de Wazuh** n'a pas le magasin de certificats CA → erreur `CERTIFICATE_VERIFY_FAILED`. Corrigé en chargeant un bundle CA (`/etc/ssl/certs/ca-certificates.crt`) dans le contexte SSL.
- Discord **bloque le User-Agent par défaut** de Python (`Python-urllib`) → erreur `403 Forbidden`. Corrigé en ajoutant un header `User-Agent` custom.

Le script complet est dans le dépôt (`phase2/integrations/custom-discord`).

**Tester :** lancer l'attaque hydra (section 2b) → l'alerte `100210` niveau 14 → un message apparaît dans le salon Discord avec le log de l'attaque.

**À dire :** *« Dès qu'une compromission est détectée, l'équipe est notifiée en temps réel sur Discord, avec le détail de l'événement — plus besoin de surveiller le dashboard en permanence. »*

> ⚠️ **Sécurité (à documenter) :** l'URL du webhook est un **secret** — jamais dans git, à régénérer si exposée. La désactivation éventuelle de la vérification TLS n'est qu'un repli de lab ; en production, on fournit un vrai bundle CA.

---

## 5. Rétention & cycle de vie des logs

**Ce qu'on démontre :** l'exigence « log retention & lifecycle management » du cahier — les alertes sont conservées un temps défini puis supprimées automatiquement, pour maîtriser le stockage et respecter les durées légales de conservation (aspect GDPR).

**Comment ça marche :** une politique **ISM** (Index State Management) de l'indexer gère le cycle de vie des indices `wazuh-alerts-*` : ici, suppression après **90 jours**.

**Création de la politique** (via l'API de l'indexer, depuis l'hôte Docker) :

```bash
curl -k -u admin:SecretPassword -X PUT "https://localhost:9200/_plugins/_ism/policies/wazuh-alerts-retention" \
  -H "Content-Type: application/json" -d '{
  "policy": {
    "description": "Retention 90 jours des alertes Wazuh",
    "default_state": "hot",
    "states": [
      { "name": "hot", "actions": [], "transitions": [ { "state_name": "delete", "conditions": { "min_index_age": "90d" } } ] },
      { "name": "delete", "actions": [ { "delete": {} } ], "transitions": [] }
    ],
    "ism_template": [ { "index_patterns": ["wazuh-alerts-*"], "priority": 100 } ]
  }
}'
```

**Appliquer aux indices existants** (les nouveaux sont pris automatiquement via `ism_template`) :

```bash
curl -k -u admin:SecretPassword -X POST "https://localhost:9200/_plugins/_ism/add/wazuh-alerts-*" \
  -H "Content-Type: application/json" -d '{"policy_id":"wazuh-alerts-retention"}'
```

**Où vérifier :** Dashboard → *Indexer management → State management policies* (ou `_plugins/_ism/explain/wazuh-alerts-*`).

**À dire :** *« Les alertes sont conservées 90 jours puis purgées automatiquement — on maîtrise le stockage et on respecte une politique de rétention, ce qui répond aux exigences GDPR sur la durée de conservation des données. »*

---

## 6. Durcissement (ISO 27001) — à documenter

Points de durcissement à mentionner dans le volet conformité (certains non appliqués volontairement pour ne pas casser la stack de démo) :

- **Changer le mot de passe par défaut** `admin` / `SecretPassword` (le défaut public de `wazuh-docker`). Procédure officielle : doc Wazuh → *Deployment → Docker → Change the passwords* (régénération du hash, `internal_users.yml`, `securityadmin`, mise à jour des références dashboard/manager). **À faire avant toute mise en production.**
- **Secrets hors dépôt** : URL de webhook, mots de passe — jamais dans git.
- **TLS** : en production, fournir un vrai bundle CA aux intégrations (pas de vérification désactivée).
- **Accès réseau** : restreindre l'exposition des ports (dashboard, API, indexer) au strict nécessaire.

---

## Aide-mémoire

```bash
# Etat de la stack
sudo docker compose ps

# Agents
sudo docker exec single-node-wazuh.manager-1 /var/ossec/bin/agent_control -ls

# Alertes en direct
sudo docker exec single-node-wazuh.manager-1 tail -f /var/ossec/logs/alerts/alerts.log

# Tester une regle
sudo docker exec -it single-node-wazuh.manager-1 /var/ossec/bin/wazuh-logtest
```
