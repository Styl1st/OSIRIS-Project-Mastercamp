# Phase 1 — Déploiement minimal (all-in-one)

Tous les composants Wazuh (manager, indexer, dashboard) sur **une seule VM Ubuntu** : `wazuh-server` (192.168.195.134).

## Ordre d'exécution (sur la VM serveur)

| # | Script | Fait quoi |
|---|---|---|
| 1 | `scripts/01-prepare-system.sh` | Hostname, IP statique, update, prérequis |
| 2 | `scripts/02-install-wazuh-server.sh` | Install Wazuh 4.14 all-in-one |
| 3 | `scripts/03-post-install-check.sh` | Vérifie services, ports, dashboard |
| 4 | `scripts/04-enable-syslog-collection.sh` | Active la réception syslog 514/udp |
| 5 | `scripts/05-setup-agent-groups.sh` | Crée les groupes `linux`/`windows` + déploie les `agent.conf` partagés |

> **Important** : lancer le script 5 **avant** d'enrôler les agents. Sans les groupes, l'enrôlement échoue avec `ERROR: Invalid group: linux. Unable to add agent`.

Puis enrôler les agents → voir `../agents/`.

## Configs (`configs/`)

- `shared-agent-linux.conf` / `shared-agent-win