# Guide pas-à-pas — Serveur Wazuh sur la VM Ubuntu (VMware)

Pour le rôle **Infrastructure & Déploiement**. VM Ubuntu fraîche → serveur Wazuh all-in-one opérationnel.

## 0. Côté VMware (avant de toucher à Ubuntu)

1. VM éteinte → `VM > Settings` : **8 Go RAM, 4 vCPU, disque ≥ 50 Go**, carte réseau en **NAT (VMnet8)**.
2. `Edit > Virtual Network Editor` → sélectionner VMnet8 → noter le **Subnet IP** (ex: `192.168.195.0`).
   - Si différent de `192.168.195.0` : soit le changer pour `192.168.195.0` (bouton *Change Settings*), soit adapter les IPs dans les scripts/docs du repo.
   - La passerelle NAT est toujours le **.2** du subnet (`NAT Settings` pour vérifier).
3. Démarrer la VM.

## 1. Récupérer le repo sur la VM

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/Styl1st/OSIRIS-Project-Mastercamp.git
cd OSIRIS-Project-Mastercamp/phase1/scripts
```

## 2. Préparer le système (IP statique, prérequis)

Éditer si besoin les variables en tête de `01-prepare-system.sh` (IP/gateway selon ton VMnet8), puis :

```bash
sudo bash 01-prepare-system.sh
```

→ hostname `wazuh-server`, IP statique `192.168.195.134`, système à jour.
Vérifier : `ip a` (IP correcte) et `ping -c2 google.com` (Internet OK).

📸 **Snapshot VMware : `01-ubuntu-clean`**

## 3. Installer Wazuh all-in-one (~10-15 min)

```bash
sudo bash 02-install-wazuh-server.sh
```

Le script télécharge l'assistant officiel 4.14 et lance `wazuh-install.sh -a`.
**Noter le mot de passe `admin` affiché à la fin** (les garder hors du git !).

Mots de passe à tout moment :

```bash
sudo tar -O -xvf /root/wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt
```

## 4. Vérifier

```bash
sudo bash 03-post-install-check.sh
```

Tout doit être OK : services (manager, indexer, dashboard, filebeat), ports (443, 1514, 1515, 9200, 55000), dashboard HTTPS.

Depuis **l'hôte Windows** : ouvrir `https://192.168.195.134` (avertissement certificat auto-signé = normal → Continuer) → login `admin`.

📸 **Snapshot VMware : `02-wazuh-installed`**

## 5. Activer la réception syslog (firewall/switch)

```bash
sudo bash 04-enable-syslog-collection.sh
```

## 6. Déployer la config centralisée des agents

```bash
cd ~/OSIRIS-Project-Mastercamp
sudo /var/ossec/bin/agent_groups -a -g linux -q
sudo /var/ossec/bin/agent_groups -a -g windows -q
sudo cp phase1/configs/shared-agent-linux.conf   /var/ossec/etc/shared/linux/agent.conf
sudo cp phase1/configs/shared-agent-windows.conf /var/ossec/etc/shared/windows/agent.conf
sudo chown wazuh:wazuh /var/ossec/etc/shared/*/agent.conf
sudo systemctl restart wazuh-manager
```

## 7. Déployer les règles custom (avec le rôle Détection)

```bash
sudo cp rules/local_rules.xml /var/ossec/etc/rules/local_rules.xml
sudo chown wazuh:wazuh /var/ossec/etc/rules/local_rules.xml
sudo systemctl restart wazuh-manager
```

## 8. Premier agent : l'hôte Windows (test rapide)

Sur l'hôte Windows (PowerShell admin) — il voit la VM via la carte VMnet8 :

```powershell
cd <repo>\agents\windows
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install-agent.ps1 -Manager 192.168.195.134 -AgentGroup windows
```

Dashboard → Agents → l'agent doit passer `Active` en ~1 min.

📸 **Snapshot VMware : `03-agents-connected`**

## Dépannage rapide

| Problème | Piste |
|---|---|
| Dashboard inaccessible depuis l'hôte | `ping 192.168.195.134` depuis l'hôte ; VM bien en NAT ; `sudo ss -tlnp \| grep 443` |
| Install échoue (RAM) | Relancer avec `-i` (le script le fait seul si <8 Go) |
| Agent `Never connected` | IP manager erronée, ou 1514-1515 bloqués ; voir `ossec.log` côté agent |
| Service KO | `sudo journalctl -u wazuh-manager -n 50` (ou indexer/dashboard) |
| Réinstaller proprement | `sudo bash wazuh-install.sh -u` (désinstalle tout) puis relancer le script 02 |

## Suite (rôle infra)

1. Créer les VMs `srv-linux` (.20) et `srv-web` (.21) → agents via `agents/linux/install-agent.sh`
2. pfSense (.5) → syslog (voir `agents/README.md`)
3. Préparer la phase 2 (3 nœuds) : `phase2/README.md`
