# Règles custom — rôle Détection & Règles

`local_rules.xml` = point de départ avec les 3 use cases imposés, mappés MITRE ATT&CK.

## Déploiement (sur le serveur Wazuh)

```bash
sudo cp local_rules.xml /var/ossec/etc/rules/local_rules.xml
sudo chown wazuh:wazuh /var/ossec/etc/rules/local_rules.xml
sudo systemctl restart wazuh-manager
```

## Use cases couverts

| ID | Use case | MITRE | Déclencheur |
|---|---|---|---|
| 100100 | Brute-force SSH | T1110 | 8× échec SSH / 120 s / même IP |
| 100101 | Brute-force Windows | T1110 | 8× event 4625 / 120 s |
| 100110-111 | FIM fichiers critiques | T1098, T1565.001 | /etc/passwd, shadow, sudoers, authorized_keys |
| 100120 | Processus suspect Linux | T1059 | nc, socat, xmrig… dans la liste de processus |
| 100121 | Outil offensif Windows | T1003 | mimikatz, psexec… (nécessite Sysmon) |
| 100122 | PowerShell encodé | T1059.001 | `-EncodedCommand` |

## Tester une règle sans attaque réelle

```bash
sudo /var/ossec/bin/wazuh-logtest
# coller une ligne de log (ex: échec sshd), vérifier la règle qui matche
```

## Conventions

- IDs custom : **100000+** (réservés à l'usage local), tranche OSIRIS : 1001xx par use case.
- Toujours ajouter `<mitre><id>Txxxx</id></mitre>` → visible dans le dashboard MITRE ATT&CK.
- Niveau ≥ 12 = critique (penser à l'alerting email/webhook en phase 2).
