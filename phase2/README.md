# Phase 2 — Architecture distribuée (multi-nœuds)

Séparation des responsabilités sur 3 VMs :

| VM | IP | Composant |
|---|---|---|
| `wazuh-server` | 192.168.100.10 | Manager (traitement, règles) |
| `wazuh-indexer` | 192.168.100.11 | Indexation / stockage |
| `wazuh-dashboard` | 192.168.100.12 | Visualisation |

## Principe d'installation

Le même assistant `wazuh-install.sh` gère le mode distribué via un fichier `config.yml` :

```bash
# 1. Sur une machine (ex: le futur indexer) — générer les certificats pour TOUS les nœuds
curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh
curl -sO https://packages.wazuh.com/4.14/config.yml   # ou utiliser configs/config.yml de ce repo
sudo bash wazuh-install.sh --generate-config-files    # → wazuh-install-files.tar

# 2. Copier wazuh-install-files.tar sur chaque nœud (scp), puis :
sudo bash wazuh-install.sh --wazuh-indexer node-indexer     # sur .11
sudo bash wazuh-install.sh --start-cluster                  # sur .11 (initialise le cluster)
sudo bash wazuh-install.sh --wazuh-server node-server       # sur .10
sudo bash wazuh-install.sh --wazuh-dashboard node-dashboard # sur .12
```

`configs/config.yml` du repo contient déjà le plan IP ci-dessus.

## Fonctionnalités à livrer en phase 2

- [ ] Règles custom + corrélation multi-systèmes (→ `rules/`)
- [ ] Détection de vulnérabilités (activée par défaut dans `ossec.conf` : `<vulnerability-detection>`)
- [ ] Alerting email (`<global><email_notification>`) et/ou webhook → `configs/alerting-email.xml`
- [ ] Rétention / cycle de vie : politique ISM sur `wazuh-alerts-*` (Dashboard → Index Management → 90 j)
- [ ] Conformité ISO 27001 : modules SCA + rapports dashboard (Modules → Security configuration assessment)

## Pré-requis VM supplémentaires

indexer : 4 Go RAM min (8 recommandé) • dashboard : 4 Go • manager : 4 Go.
Adapter le plan VMware selon la RAM disponible sur l'hôte.
