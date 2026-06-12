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

**Pourquoi Wazuh ?** Open-source, SIEM + XDR unifié (agents EDR, FI