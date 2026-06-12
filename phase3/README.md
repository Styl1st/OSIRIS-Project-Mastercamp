# Phase 3 — Conteneurisation + fonctions avancées

## Infrastructure cible

- Cluster multi-nœuds conteneurisé (**Docker Compose**, option Kubernetes)
- Load balancing des managers (NGINX en amont des workers, ports 1514)
- Déploiement reproductible (IaC)

## Déploiement Docker (base officielle)

```bash
# Sur une VM Docker (8+ Go RAM)
sudo sysctl -w vm.max_map_count=262144   # requis par l'indexer
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-wazuh.conf

git clone https://github.com/wazuh/wazuh-docker.git -b v4.14.5
cd wazuh-docker/single-node            # ou multi-node/ pour le cluster
docker compose -f generate-indexer-certs.yml run --rm generator   # certificats
docker compose up -d
```

Le dossier `multi-node/` du repo officiel fournit : 2 managers (master + worker), 3 indexers, 1 dashboard, et un **NGINX load balancer** pour les agents — base directe pour cette phase.

## Fonctionnalités avancées à livrer

| Fonctionnalité | Piste d'implémentation | Rôle concerné |
|---|---|---|
| Threat intelligence | Intégration VirusTotal (`<integration>` ossec.conf) ou MISP | Détection / Intégrations |
| Mapping MITRE ATT&CK | Natif dashboard + `<mitre>` dans les règles custom | Détection |
| Réponse automatique | Active Response (ex: `firewall-drop` sur brute-force 100100) | Infra + Détection |
| Analyse comportementale | Sysmon + règles fréquence/corrélation | Détection |
| Cloud (AWS/Azure/GCP) | Modules wodle `aws-s3`, `azure-logs`, `gcp-pubsub` | Intégrations |
| IDS | Suricata sur srv-web → logs EVE JSON ingérés par l'agent | Intégrations |
| Active Directory | Agent sur contrôleur de domaine + event channels | Intégrations |

### Exemple Active Response (firewall-drop sur brute-force)

```xml
<!-- ossec.conf (manager) -->
<active-response>
  <command>firewall-drop</command>
  <location>local</location>
  <rules_id>100100</rules_id>
  <timeout>600</timeout>
</active-response>
```

## Conformité

- PCI DSS : dashboard Modules → PCI DSS (tags `pci_dss_*` déjà posés dans `rules/local_rules.xml`)
- GDPR : chiffrement TLS bout-en-bout (déjà natif), contrôle d'accès RBAC dashboard, rétention 90 j
