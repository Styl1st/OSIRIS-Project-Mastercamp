# =============================================================================
# install-agent.ps1 — Installe l'agent Wazuh sur Windows
# Rôle : Agents & Intégrations
# Usage : PowerShell en ADMINISTRATEUR :
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\install-agent.ps1 -Manager 192.168.195.134 -AgentGroup windows
# =============================================================================
param(
    [string]$Manager    = "192.168.195.134",
    [string]$AgentName  = $env:COMPUTERNAME,
    [string]$AgentGroup = "windows",
    [string]$Version    = "4.14.5-1"
)

$ErrorActionPreference = "Stop"
$msi = "$env:TEMP\wazuh-agent.msi"
$url = "https://packages.wazuh.com/4.x/windows/wazuh-agent-$Version.msi"

Write-Host "[1/3] Téléchargement de l'agent Wazuh $Version"
Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing

Write-Host "[2/3] Installation (manager: $Manager, nom: $AgentName, groupe: $AgentGroup)"
Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /q WAZUH_MANAGER=`"$Manager`" WAZUH_AGENT_NAME=`"$AgentName`" WAZUH_AGENT_GROUP=`"$AgentGroup`" WAZUH_REGISTRATION_SERVER=`"$Manager`"" -Wait

Write-Host "[3/3] Démarrage du service"
Start-Service WazuhSvc
Start-Sleep -Seconds 5

if ((Get-Service WazuhSvc).Status -eq "Running") {
    Write-Host "[OK] Agent '$AgentName' démarré. Vérifier le statut 'Active' dans le dashboard." -ForegroundColor Green
} else {
    Write-Host "[ERREUR] Service WazuhSvc non démarré. Voir C:\Program Files (x86)\ossec-agent\ossec.log" -ForegroundColor Red
    exit 1
}
