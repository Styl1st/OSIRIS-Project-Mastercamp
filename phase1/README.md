# Phase 1 — Déploiement minimal SIEM/XDR (Wazuh all-in-one)

Première phase du projet OSIRIS : déployer une plateforme **SIEM/XDR open-source** complète sur une architecture simple, où tous les composants Wazuh tournent sur **une seule machine** (déploiement *all-in-one*), et y raccorder des sources de données hétérogènes (Linux, Windows, serveur web, firewall, switch).

> **État : terminée et validée.** 5 sources intégrées avec détection sur chacune. Seul le volet documentaire GDPR reste à rédiger (rôle « Compliance & Doc »).

---

## 1. Objectif de la phase

Valider le concept SIEM/XDR de bout en bout :

- collecte **centralisée** des logs de plateformes variées ;
- **détection** d'événements de sécurité de base ;
- **surveillance d'intégrité des fichiers** (FIM) ;
- **dashboard** de visualisation ;
- conformité de base (les alertes sont mappées **GDPR / PCI DSS / HIPAA / NIST**).

---

## 2. Architecture

```
                          Réseau VMnet8 (NAT) — 192.168.195.0/24

   ┌─────────────────────────┐
   │   SERVEUR WAZUH (.134)   │   all-in-one :
   │  manager + indexer +     │   - Manager  (analyse, règles, alertes)
   │  dashboard + filebeat    │   - Indexer  (stockage/indexation, OpenSearch)
   │   Ubuntu — 8 Go RAM      │   - Dashboard (https://192.168.195.134)
   └───────────▲─────────────┘
               │
   ┌───────────┴───────────────────────────────────────────────┐
   │                                                            │
 AGENTS (port 1514/1515 TCP)                       AGENTLESS (syslog 514/UDP)
   │                                                            │
   ├── srv-linux  (Ubuntu, agent)   groupe "linux"     ┌────────┴─────────┐
   │     + Apache  (= Web Server)                       │ pfSense (.136)   │ firewall
   ├── ws-windows (Windows, agent)  groupe "windows"    │ Switch Cisco     │ (réel/simulé)
   │                                                    └──────────────────┘
   └── (autres agents éventuels)
```

| Composant | Rôle | Repère |
|---|---|---|
| Wazuh Manager | Collecte, décodage, moteur de règles, alertes, enrôlement | sur le serveur |
| Wazuh Indexer | Stockage et indexation des événements (fork OpenSearch) | sur le serveur |
| Wazuh Dashboard | Visualisation, dashboards sécurité, conformité, MITRE | `https://192.168.195.134` |
| Agents Wazuh | Collecte locale (logs, FIM, inventaire) — Linux/Windows/web | machines surveillées |
| Syslog (agentless) | Réception des logs firewall/switch sans agent | port 514/UDP |

> **Les adresses IP sont propres à cet environnement.** Chez un autre membre de l'équipe, le serveur aura une autre IP — la trouver avec `hostname -I` et l'adapter dans les commandes ci-dessous.

---

## 3. Prérequis

- **VMware** (Workstation/Player), VMs sur le même réseau **VMnet8 (NAT)**.
- Serveur Wazuh : Ubuntu, **≥ 8 Go RAM recommandés** (l'all-in-one est gourmand : manager + indexer Java + dashboard).
- Accès Internet sur chaque VM (téléchargement des paquets Wazuh).
- Versions de référence utilisées : **Wazuh 4.14.5**, **pfSense CE 2.8.1**.

---

## 4. Installation du serveur (scripts `phase1/scripts/`)

À exécuter **dans l'ordre, sur la VM serveur** :

| # | Script | Rôle |
|---|---|---|
| 1 | `01-prepare-system.sh` | Hostname, IP statique, mise à jour, prérequis |
| 2 | `02-install-wazuh-server.sh` | Installe Wazuh 4.14 all-in-one (manager + indexer + dashboard) |
| 3 | `03-post-install-check.sh` | Vérifie services, ports, dashboard, filebeat |
| 4 | `04-enable-syslog-collection.sh` | Active la réception syslog 514/UDP (sources agentless) |
| 5 | `05-setup-agent-groups.sh` | Crée les groupes `linux`/`windows` + déploie les `agent.conf` partagés |

```bash
sudo bash 01-prepare-system.sh
sudo bash 02-install-wazuh-server.sh        # ~10-15 min
sudo bash 03-post-install-check.sh          # doit afficher 12 OK / 0 FAIL
sudo bash 05-setup-agent-groups.sh          # AVANT d'enrôler les agents
sudo bash 04-enable-syslog-collection.sh    # quand on ajoute firewall/switch
```

> **Important :** lancer le script **05 avant** d'enrôler le moindre agent. Sans les groupes, l'enrôlement échoue avec `ERROR: Invalid group: linux. Unable to add agent`.

**Récupérer les identifiants du dashboard** (à conserver hors du dépôt git) :

```bash
sudo tar -O -xvf /root/wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt
```

Dashboard : `https://192.168.195.134` — utilisateur `admin`.

---

## 5. Enrôlement des agents (plateformes surveillées)

Les scripts d'agent sont dans `agents/`. Le paramètre `WAZUH_MANAGER` (Linux) / `-Manager` (Windows) **doit pointer vers l'IP du serveur**.

### Linux Server (et Web Server)

Sur la VM Ubuntu cliente :

```bash
git clone https://github.com/Styl1st/OSIRIS-Project-Mastercamp.git
cd OSIRIS-Project-Mastercamp/agents/linux
sudo WAZUH_MANAGER=192.168.195.134 AGENT_NAME=srv-linux AGENT_GROUP=linux bash install-agent.sh
```

Le **serveur web** est ici hébergé sur la même VM Linux (Apache installé dessus). Pour une plateforme distincte, refaire la procédure sur une 2ᵉ VM avec `AGENT_NAME=srv-web`.

### Windows Workstation

PowerShell **en Administrateur** (sans dépendre du dépôt) :

```powershell
$msi = "$env:TEMP\wazuh-agent.msi"
Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.5-1.msi" -OutFile $msi -UseBasicParsing
Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /q WAZUH_MANAGER=`"192.168.195.134`" WAZUH_AGENT_NAME=`"ws-windows`" WAZUH_AGENT_GROUP=`"windows`" WAZUH_REGISTRATION_SERVER=`"192.168.195.134`"" -Wait
Start-Service WazuhSvc
```

### Vérifier l'enrôlement (sur le serveur)

```bash
sudo /var/ossec/bin/agent_control -ls
```

Chaque machine doit apparaître en **`Active`** (visible aussi dans le dashboard → *Agents*).

---

## 6. Sources agentless (firewall & switch via syslog)

Le serveur écoute le **syslog sur 514/UDP** (activé par le script `04`, autorisé pour `192.168.195.0/24`). N'importe quel équipement émettant du syslog vers `192.168.195.134:514` remonte alors **sans agent**.

### Firewall pfSense

1. VM pfSense sur VMnet8 (WAN = VMnet8 pour joindre le serveur ; LAN pour l'admin).
2. GUI pfSense → **Status → System Logs → Settings → Remote Logging** :
   - Enable Remote Logging : ☑
   - Remote log servers : `192.168.195.134:514`
   - Remote Syslog Contents : *Everything* (ou Firewall + System events)

### Switch (Cisco IOS)

Même mécanisme — sur un vrai switch :

```
logging host 192.168.195.134
logging trap informational
```

Wazuh reconnaît nativement les logs Cisco (décodeur `cisco-ios`), ex. la règle **4724** (« Failed login to the router », niveau 9).

---

## 7. Configuration centralisée (`phase1/configs/`)

Chaque groupe d'agents reçoit automatiquement une config partagée déployée par le script `05` dans `/var/ossec/etc/shared/<groupe>/agent.conf` :

- **`shared-agent-linux.conf`** : FIM temps réel (`/etc`, `/usr/bin`, `/usr/sbin`, `/root/.ssh`, `/home`), collecte `auth.log` + `syslog`, **logs Apache** (serveur web), surveillance des processus. Les caches volatils (`/snap`, `.cache`, `gvfs-metadata`…) sont ignorés pour éviter le bruit.
- **`shared-agent-windows.conf`** : FIM (registre + `drivers\etc`), journaux d'événements Security/System/Application, Sysmon et PowerShell.

Modifier ces fichiers puis relancer le script `05` (ou recopier vers `/var/ossec/etc/shared/...`) pour pousser les changements à tous les agents du groupe.

---

## 8. Validation / tests

| Source | Test | Résultat attendu |
|---|---|---|
| FIM Linux | `echo "# test $(date)" \| sudo tee -a /etc/hosts` (sur l'agent) | Règle **550** « Integrity checksum changed » |
| Auth Linux/Windows | Échecs de connexion (mauvais mot de passe) | Règles **5503 / 5710 / 60xxx**, brute-force au-delà du seuil |
| Web | `curl "http://localhost/?id=1+union+select+1,2,3--"` | Règles **31101** (4xx), **31103/31106** (attaque web) |
| Firewall pfSense | Mauvais login sur le GUI pfSense | Règle **2501** « syslog: User authentication failure » |
| Switch Cisco | `wazuh-logtest` avec une ligne `%SEC_LOGIN-4-LOGIN_FAILED` | Décodeur `cisco-ios`, règle **4724** niveau 9 |

Suivre les alertes en direct sur le serveur :

```bash
sudo tail -f /var/ossec/logs/alerts/alerts.log
```

Tester le moteur de règles sans générer d'événement réel :

```bash
sudo /var/ossec/bin/wazuh-logtest
```

---

## 9. Conformité (GDPR / PCI DSS / HIPAA / NIST)

Wazuh **mappe automatiquement** chaque alerte aux référentiels de conformité : on retrouve les tags `gdpr_IV_32.2`, `pci_dss_10.2.5`, `hipaa_164.312.b`, `nist_800_53_*` sur les alertes. Le dashboard fournit des vues dédiées (module *Compliance / GDPR*). Ce mappage constitue la base du livrable GDPR (rétention des logs, traçabilité des accès, protection des données).

---

## 10. Dépannage (problèmes rencontrés & solutions)

| Symptôme | Cause | Solution |
|---|---|---|
| `Wazuh indexer already installed` | Réinstallation sur une install partielle | `sudo bash /root/wazuh-install.sh -a -i -o` (option `-o` = overwrite) |
| `curl: command not found` (install agent) | Paquet absent sur Ubuntu minimal | `sudo apt install -y curl gnupg` |
| `Le dépôt file:/cdrom ... ne contient plus de Release` | CD d'install référencé dans apt | Désactiver : `sudo mv /etc/apt/sources.list.d/cdrom.sources{,.disabled}` |
| `ERROR: Invalid group: linux. Unable to add agent` | Groupe non créé sur le manager | Lancer le script `05` (ou `agent_groups -a -g linux`) **avant** l'enrôlement |
| `Error 1017 - Some Wazuh daemons are not ready (modulesd)` | modulesd lent à démarrer (téléchargement flux CVE) | Attendre 1-3 min ; `sudo systemctl restart wazuh-manager` puis revérifier |
| Pas d'accès Internet sur une VM | Mauvais réseau VMware | Carte réseau en **NAT (VMnet8)**, puis `sudo dhclient` ; DNS : `nameserver 8.8.8.8` |
| Copier-coller hôte → VM serveur impossible | Pas d'intégration VMware (serveur sans bureau) | **Piloter en SSH** : `ssh wazuh-server@192.168.195.134` |
| GUI pfSense inaccessible depuis le WAN | pfSense bloque l'admin sur le WAN | Console → `8` (Shell) → `pfctl -d` (réactiver ensuite avec `pfctl -e`) |
| Bruit FIM (`gvfs`, `nautilus`, caches) | Fichiers volatils dans `/home` | Ignores ajoutés dans `shared-agent-linux.conf` |

---

## 11. Commandes utiles (aide-mémoire)

```bash
# État des démons du manager
sudo /var/ossec/bin/wazuh-control status

# Liste des agents et leur statut
sudo /var/ossec/bin/agent_control -ls

# Gérer les groupes
sudo /var/ossec/bin/agent_groups -l
sudo /var/ossec/bin/agent_groups -a -g <groupe>

# Suivre les alertes
sudo tail -f /var/ossec/logs/alerts/alerts.log

# Tester une règle/décodeur
sudo /var/ossec/bin/wazuh-logtest

# Vérifier l'écoute du syslog agentless
sudo ss -uln | grep 514
```

---

## 12. Ports utilisés

| Port | Protocole | Usage |
|---|---|---|
| 443 | TCP | Dashboard (HTTPS) |
| 1514 | TCP | Communication agents → manager |
| 1515 | TCP | Enrôlement des agents |
| 9200 | TCP | Wazuh Indexer (OpenSearch) |
| 55000 | TCP | API Wazuh |
| 514 | UDP | Réception syslog (firewall/switch agentless) |

---

## 13. Suite — Phase 2

Architecture **multi-nœuds** : éclater le manager, l'indexer et le dashboard sur des VMs dédiées, ajouter des **règles de corrélation custom**, l'**alerting email/webhook**, la **détection de vulnérabilités** et la **politique de rétention**. Voir `phase2/`.
