# Phase 2 — Architecture distribuée multi-nœuds (conteneurs Docker)

Séparation des responsabilités **manager / indexer / dashboard** sur des **nœuds dédiés**, mais en **conteneurs Docker** plutôt qu'en VMs séparées — plus léger, plus rapide, peu de disque, tout en respectant le principe du cahier des charges (composants isolés, chacun sa config, son réseau).

> **Pourquoi Docker et pas 3 VMs ?** Le déploiement Docker « single-node » de Wazuh lance en réalité **3 conteneurs distincts** (`wazuh.manager`, `wazuh.indexer`, `wazuh.dashboard`) : c'est bien une architecture multi-nœuds à responsabilités séparées, sans le coût de 3 machines virtuelles complètes.

---

## 1. Découpage Phase 2 / Phase 3

- **Phase 2 (ici)** : architecture **distribuée multi-nœuds** (3 conteneurs dédiés) + règles de corrélation, détection de vulnérabilités, alerting, rétention des logs, conformité ISO 27001.
- **Phase 3 (plus tard)** : passage à un **vrai cluster** haute disponibilité (plusieurs managers/indexers, load balancing), **orchestration** (Docker Swarm / Kubernetes) et fonctionnalités avancées (threat intelligence, MITRE ATT&CK, réponse automatisée, cloud, AD/IDS).

Ce découpage garde chaque phase distincte et défendable.

---

## 2. Architecture cible

```
                 HÔTE DOCKER (1 VM Ubuntu ou l'hôte via Docker Desktop)
                 IP ex. 192.168.195.140

   ┌──────────────────────────────────────────────────────────────┐
   │  Réseau Docker interne  (wazuh-docker_default)                │
   │                                                               │
   │   ┌───────────────┐   ┌───────────────┐   ┌────────────────┐  │
   │   │ wazuh.manager │──▶│ wazuh.indexer │◀──│ wazuh.dashboard│  │
   │   │  (traitement, │   │ (stockage /   │   │ (visualisation)│  │
   │   │   règles)     │   │  indexation)  │   │                │  │
   │   └───────▲───────┘   └───────────────┘   └────────┬───────┘  │
   │           │                                        │          │
   └───────────┼────────────────────────────────────────┼──────────┘
      ports 1514/1515 (agents)                    port 443 (dashboard)
               │                                        │
        Agents Phase 1 (srv-linux, ws-windows, pfSense…) et navigateur
        → pointent vers l'IP de l'HÔTE DOCKER
```

Chaque conteneur = un nœud dédié. Les agents et le navigateur se connectent à **l'IP de l'hôte Docker** (les ports sont publiés par le `docker-compose`).

---

## 3. Prérequis

- **Une machine avec Docker** : soit **une VM Ubuntu unique** (recommandé, le plus simple), soit ton **hôte Windows via Docker Desktop**.
- **RAM** : ~5-6 Go disponibles pour la stack (l'indexer/OpenSearch est le plus gourmand).
- **Docker Engine + plugin `docker compose`**. Installation Docker sur Ubuntu : https://docs.docker.com/engine/install/ubuntu/
- **`vm.max_map_count = 262144`** (exigé par l'indexer OpenSearch) — le script de déploiement s'en occupe.

---

## 4. Déploiement (automatisé)

Un script fait tout : vérifie Docker, règle `vm.max_map_count`, clone le dépôt officiel `wazuh-docker` à la bonne version, génère les certificats et démarre la stack.

```bash
sudo bash phase2/scripts/deploy-wazuh-docker.sh
```

Ou **manuellement**, étape par étape :

```bash
# 1. Prérequis indexer
sudo sysctl -w vm.max_map_count=262144

# 2. Récupérer le déploiement Docker officiel (adapter le tag à ta version)
git clone https://github.com/wazuh/wazuh-docker.git -b v4.14.5 --depth=1
cd wazuh-docker/single-node

# 3. Générer les certificats (manager + indexer + dashboard)
docker compose -f generate-indexer-certs.yml run --rm generator

# 4. Démarrer les 3 nœuds
docker compose up -d

# 5. Suivre le démarrage (l'indexer met ~1-2 min)
docker compose ps
docker compose logs -f wazuh.manager
```

**Accès dashboard :** `https://<IP-de-l-hôte-docker>` — utilisateur `admin`.

> ⚠️ **Sécurité :** le mot de passe par défaut est défini en clair dans `docker-compose.yml`. **Change-le impérativement** avant toute démo « propre » (procédure : doc Wazuh → *Docker → Change the passwords*). À mentionner dans le volet ISO 27001.

**Arrêter / relancer :**

```bash
docker compose down          # arrêt (garde les données/volumes)
docker compose up -d         # relance
docker compose down -v       # arrêt + SUPPRESSION des données (reset complet)
```

---

## 5. Reconnecter les agents de la Phase 1

Tes agents existants (`srv-linux`, `ws-windows`) et pfSense peuvent pointer vers ce nouveau manager. Il suffit de changer l'adresse du manager côté agent :

- **Linux** : dans `/var/ossec/etc/ossec.conf`, mettre `<address>` = IP de l'hôte Docker, puis `sudo systemctl restart wazuh-agent`.
- **Windows** : idem dans `C:\Program Files (x86)\ossec-agent\ossec.conf`, puis redémarrer le service `WazuhSvc`.
- **pfSense / switch** : pointer le syslog vers l'IP de l'hôte Docker (port 514/UDP à publier dans le compose si besoin).

> Astuce : tu peux garder la Phase 1 (all-in-one) intacte pour sa démo, et n'enrôler qu'un agent de test sur la stack Phase 2.

---

## 6. Fonctionnalités à livrer en Phase 2

- [ ] **Règles custom + corrélation multi-systèmes** — ajouter des règles dans le conteneur manager (`/var/ossec/etc/rules/local_rules.xml`), soit via un volume monté, soit `docker exec`. Objectif : corréler des événements de plusieurs sources (ex. échec SSH **puis** création de compte).
- [ ] **Détection de vulnérabilités** — activée par défaut en 4.x (`<vulnerability-detection>` dans `ossec.conf`). Vérifier dans le dashboard → module *Vulnerability Detection*.
- [ ] **Alerting email / webhook** — intégrer `configs/alerting-email.xml` dans la conf du manager (nécessite un relais SMTP joignable). Alternative moderne : intégration **webhook** (Slack/Discord) via `integratord`.
- [ ] **Rétention / cycle de vie des logs** — politique **ISM** sur les indices `wazuh-alerts-*` (Dashboard → *Indexer management → Index policies*), ex. suppression après 90 jours.
- [ ] **Conformité ISO 27001 / HIPAA** — modules **SCA** (Security Configuration Assessment) et vues de conformité du dashboard ; documenter la correspondance contrôles ↔ mesures Wazuh.

---

## 7. Répartition des tâches (équipe)

| Rôle | Tâche Phase 2 |
|---|---|
| Infrastructure | Déployer la stack Docker, publier les ports, reconnecter les agents |
| Détection & Règles | Règles de corrélation dans `rules/local_rules.xml` + mapping MITRE |
| Agents & Intégrations | Alerting email/webhook, intégrations |
| Tests & Simulation | Rejouer les scénarios (`docs/GUIDE-DEMO-ATTAQUES.md`) sur la nouvelle archi |
| Compliance & Doc | Rétention, ISO 27001, doc d'architecture |

---

## 8. Vers la Phase 3

- Passer du « single-node » (3 conteneurs) au **`multi-node`** de `wazuh-docker` : **cluster** de plusieurs managers + plusieurs indexers, avec **load balancing**.
- **Orchestration** : Docker Swarm ou **Kubernetes**.
- Fonctionnalités avancées : **threat intelligence**, cartographie **MITRE ATT&CK**, **réponse automatisée** (active response), intégrations **cloud / IDS / Active Directory**.

---

## Annexe — Alternative en VMs (si strictement exigé)

Si la soutenance impose des machines séparées, l'installation distribuée classique via `wazuh-install.sh` + `configs/config.yml` (3 VMs : manager, indexer, dashboard) reste possible. Voir l'historique de ce fichier / `configs/config.yml`. Prévoir ~4-8 Go RAM par nœud.
