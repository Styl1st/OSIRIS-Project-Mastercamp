# OSIRIS — Projet SIEM & XDR (EFREI Mastercamp)

Déploiement progressif d'une plateforme SIEM/XDR open-source basée sur **Wazuh 4.14** (manager + indexer + dashboard), en 3 phases : all-in-one → multi-nœuds → conteneurisé.

## Stack retenue

| Composant | Rôle |
|---|---|
| Wazuh Manager | Collecte, analyse, moteur de règles, alertes |
| Wazuh Indexer | Stockage et indexation des événements (fork OpenSearch) |
| Wazuh Dashboard | Visualisation, dashboards sécurité, MITRE ATT&CK |
| Wazuh Agents | Windows / Linux / serveur web (FIM, logs, inventaire) |
| Syslog | Collecte agentless : firewall, switch |

**Pourquoi Wazuh ?** Open-source, SIEM + XDR unifié (agents EDR, FIM, détection de vulnérabilités, active response), mapping MITRE ATT&CK natif, modules de conformité GDPR / PCI DSS / HIPAA intégrés.

## Répartition des rôles

| Rôle | Tâches |
|---|---|
| Infrastructure & Déploiement | Installation Wazuh, architecture réseau des VMs, infra phases 1→3 |
| Détection & Règles | Règles custom, use cases (brute-force, FIM, processus suspects), mapping MITRE |
| Agents & Intégrations | Agents Windows/Linux, syslog firewall/switch, IDS/AD |
| Tests & Simulation | Scripts d'attaque, validation des règles, rapports d'alerte |
| Compliance & Doc | GDPR, ISO 27001, PCI DSS, documentation |

## Structure du repo

```
docs/
  architecture/architecture-reseau.md   ← plan réseau VMware + matrice de flux
  GUIDE-INSTALLATION-WAZUH.md           ← guide pas-à-pas serveur Wazuh
phase1/   Déploiement minimal all-in-one (scripts + configs)
phase2/   Architecture distribuée 3 nœuds
phase3/   Conteneurisation Docker + fonctions avancées
agents/   Scripts d'installation des agents Windows / Linux
rules/    Règles de détection custom (local_rules.xml)
```

## Démarrage rapide (Phase 1)

```bash
# Sur la VM Ubuntu dédiée au serveur Wazuh :
sudo bash phase1/scripts/01-prepare-system.sh      # IP statique + prérequis
sudo bash phase1/scripts/02-install-wazuh-server.sh # Install all-in-one
sudo bash phase1/scripts/03-post-install-check.sh   # Vérifications
```

Dashboard : `https://<IP-serveur>` — identifiants affichés en fin d'installation.

⚠️ **Ne jamais commit** `wazuh-install-files.tar` ni `wazuh-passwords.txt` (voir `.gitignore`).
