# Récapitulatif Phase 1 — note pour l'équipe Doc & Compliance

> Document de passation : ce qui a été réalisé, comment, les décisions prises, les problèmes résolus, et ce qu'il reste à documenter (notamment le **volet GDPR**, qui vous revient). La documentation technique complète et reproductible est dans **`phase1/README.md`** — ce fichier-ci est un résumé de contexte.

---

## 1. En bref

La **Phase 1 (déploiement minimal SIEM/XDR)** est **terminée et validée**. Une plateforme **Wazuh 4.14.5** en mode *all-in-one* (manager + indexer + dashboard sur une seule VM) collecte et analyse les logs de **5 sources hétérogènes**, avec détection fonctionnelle et validée sur chacune. Chaque alerte est automatiquement mappée aux référentiels de conformité (**GDPR, PCI DSS, HIPAA, NIST**).

---

## 2. Ce qui a été réalisé (avec preuves de validation)

| Plateforme | Type | État | Validation (n° de règle Wazuh) |
|---|---|---|---|
| Serveur Wazuh all-in-one | Manager + Indexer + Dashboard | ✅ | `03-post-install-check.sh` → 12 OK |
| Linux Server | Agent | ✅ Active | FIM testé sur `/etc/hosts` → **règle 550** |
| Windows Workstation | Agent | ✅ Active | Échec d'authentification remonté |
| Web Server (Apache sur la VM Linux) | Agent | ✅ | Attaques web → **31101** (4xx), **31103/31106** (SQLi/XSS) |
| Firewall pfSense | Syslog agentless (514/UDP) | ✅ | Échec login GUI → **règle 2501** (alerte live) |
| Network Switch (Cisco) | Syslog agentless | ✅ | `wazuh-logtest` → décodeur `cisco-ios`, **règle 4724** niveau 9 |

**Fonctionnalités prouvées :** collecte centralisée · FIM temps réel · détection (auth, web, firewall) · dashboard · mapping conformité.

---

## 3. Détails techniques de référence (à reprendre dans la doc)

| Élément | Valeur |
|---|---|
| Version Wazuh | 4.14.5 |
| Version pfSense | CE 2.8.1 |
| Réseau | VMware **VMnet8 (NAT)** — `192.168.195.0/24` |
| IP serveur Wazuh | `192.168.195.134` |
| IP pfSense (WAN) | `192.168.195.136` |
| Agents | `srv-linux` (id 001), `ws-windows` (id 002) |
| Groupes d'agents | `linux`, `windows` |
| Dashboard | `https://192.168.195.134` (user `admin`) |
| Ports | 443 (dashboard), 1514 (agents), 1515 (enrôlement), 9200 (indexer), 55000 (API), 514/UDP (syslog) |

> ⚠️ Les IP sont propres à l'environnement de Dennis. Chaque membre a une IP serveur différente (VMs sur des machines perso). Dans la doc, présenter l'IP comme une variable à adapter (`hostname -I`).

---

## 4. Décisions importantes (à expliquer/justifier dans la doc)

- **Serveur web hébergé sur la même VM que l'agent Linux** (Apache installé sur `srv-linux`). Choix pragmatique pour le lab ; le cahier liste « Linux Server » et « Web Server » comme distincts, mais la capacité (collecte + détection d'attaques web) est démontrée. Une VM dédiée reste possible si la soutenance l'exige.
- **Un seul serveur Wazuh, géré par Dennis.** Comme chacun a ses VMs sur sa machine perso (IP différentes), il n'est pas pratique de partager un serveur. Les coéquipiers contribuent sur du contenu **indépendant de l'IP** : règles de détection, doc, GDPR, tests. (Option si besoin d'un serveur partagé : VPN maillé type Tailscale/ZeroTier → une IP stable pour tous.)
- **Switch simulé.** Pas de switch physique : la réception syslog agentless a été prouvée avec pfSense (vrai équipement), et le décodage d'un log switch Cisco a été validé via `wazuh-logtest` (règle 4724, niveau 9). Un vrai switch enverrait le format nativement.

---

## 5. Problèmes rencontrés & solutions (utile pour une section « retour d'expérience »)

- **Réinstallation serveur bloquée** (`indexer already installed`) → relancer l'installeur avec l'option `-o` (overwrite).
- **`curl`/`gnupg` absents** sur Ubuntu minimal lors de l'install agent → installés automatiquement (script agent corrigé).
- **Source apt `/cdrom`** cassée (CD d'install référencé) → fichier `cdrom.sources` désactivé.
- **Pas d'accès Internet sur une VM** → carte réseau à mettre en NAT (VMnet8) + DNS.
- **`Invalid group: linux`** à l'enrôlement → les groupes doivent être créés sur le manager **avant** (script `05` ajouté pour automatiser groupes + configs partagées).
- **`Error 1017 - daemons not ready` (modulesd)** → `wazuh-modulesd` met 1-3 min à démarrer (téléchargement des flux CVE) ; attendre / redémarrer le manager. Aucun problème de RAM ou disque réel (vérifié).
- **Copier-coller hôte → VM serveur impossible** (serveur sans bureau graphique) → on pilote le serveur en **SSH** depuis la machine hôte.
- **GUI pfSense bloqué sur le WAN** → désactivation temporaire du pare-feu (`pfctl -d`) pour accéder à l'admin, réactivé ensuite.
- **Bruit FIM** (caches `gvfs`/`snap`/`nautilus` dans `/home`) → règles d'`ignore` ajoutées à la config Linux.

---

## 6. Modifications apportées au dépôt git

- `phase1/scripts/02-install-wazuh-server.sh` — transmet les options (ex. `-o`) à l'installeur.
- `phase1/scripts/03-post-install-check.sh` — corrigé un bug bash (`((PASS++))`) qui produisait un faux FAIL.
- `phase1/scripts/05-setup-agent-groups.sh` — **nouveau** : crée les groupes + déploie les `agent.conf` partagés (idempotent, n'attend le manager que si nécessaire).
- `agents/linux/install-agent.sh` — installe `curl`/`gnupg` automatiquement.
- `phase1/configs/shared-agent-linux.conf` — FIM ajusté (anti-bruit) + collecte des logs Apache activée.
- `phase1/README.md` — **documentation technique complète et reproductible** de la Phase 1.

---

## 7. Ce qui reste à faire — surtout pour vous (Doc & GDPR)

Le volet **conformité GDPR** est le principal livrable restant de la Phase 1. Pistes concrètes pour le rédiger :

- **Wazuh fournit un module de conformité GDPR** : chaque règle est mappée à des articles GDPR (visibles dans les alertes sous forme de tags `gdpr_IV_32.2`, `gdpr_IV_35.7.d`, etc.). Dans le dashboard : *Modules → Compliance → GDPR*.
- Points à documenter pour le rapport :
  - **Gestion et rétention des logs** : centralisation sur l'indexer, durée de conservation, intégrité des journaux.
  - **Minimisation et protection des données** : contrôle d'accès au dashboard (compte `admin`), communications chiffrées (TLS entre agents/manager/indexer).
  - **Traçabilité / responsabilité** : journalisation des événements de sécurité et des accès (preuve d'auditabilité).
  - **Surveillance** : FIM, détection d'attaques, alerting — montrer comment ça répond aux exigences de « sécurité du traitement ».
- Capture utile pour le rapport : la sortie `wazuh-logtest` montrant une alerte avec ses tags `gdpr_*`, et le dashboard de conformité.

**Autre item (optionnel, équipe Détection) :** écrire une **règle custom** dans `rules/local_rules.xml` pour faire alerter en live les événements switch (le décodeur Cisco fonctionne, mais l'événement simulé retombe sur la règle parente niveau 0).

---

## 8. Références

- Documentation technique reproductible : **`phase1/README.md`** du dépôt.
- Documentation Wazuh : `https://documentation.wazuh.com` (sections *Compliance* et *Agents*).
- Dépôt : `https://github.com/Styl1st/OSIRIS-Project-Mastercamp`
