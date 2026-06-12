# Agents Wazuh — Windows / Linux

Scripts d'enrôlement des machines monitorées vers le serveur Wazuh (`192.168.195.134`).

## Linux (srv-linux, srv-web)

```bash
sudo WAZUH_MANAGER=192.168.195.134 AGENT_NAME=srv-linux AGENT_GROUP=linux bash linux/install-agent.sh
```

## Windows (ws-windows ou hôte VMware)

PowerShell **administrateur** :

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\windows\install-agent.ps1 -Manager 192.168.195.134 -AgentGroup windows
```

> La version exacte du MSI est paramétrable : `-Version 4.14.5-1`. Le dashboard (Agents → Deploy new agent) génère aussi la commande à jour si besoin.

## Vérification côté serveur

```bash
sudo /var/ossec/bin/agent_control -ls     # liste des agents + statut
```

Statut attendu : `Active`. Sinon vérifier : ports 1514-1515/tcp ouverts, IP manager correcte dans
`/var/ossec/etc/ossec.conf` (Linux) ou `C:\Program Files (x86)\ossec-agent\ossec.conf` (Windows).

## Agentless (firewall / switch)

Pas d'agent : envoi **syslog** vers `192.168.195.134:514/udp`
(listener activé par `phase1/scripts/04-enable-syslog-collection.sh`).

| Équipement | Configuration |
|---|---|
| pfSense | Status → System Logs → Settings → Remote Logging → `192.168.195.134:514` |
| Cisco IOS | `logging host 192.168.195.134` + `logging trap informational` |
| Autre | Tout équipement supportant syslog UDP 514 |
