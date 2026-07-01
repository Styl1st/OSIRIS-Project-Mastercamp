# Directives équipe — accès au SIEM partagé & rôles

Salut l'équipe 👋

Le SIEM Wazuh de la Phase 1 est en place et fonctionnel. Pour qu'on bosse tous dessus sans réinstaller chacun son serveur, on passe par un **VPN maillé Tailscale** : vous vous connectez à **mon** serveur Wazuh, vous voyez le dashboard, vous testez vos règles et vos attaques sur de vraies données.

Ci-dessous : comment se connecter, puis les directives pour **Détection & Règles** et **Tests & Simulation**. La doc technique complète est dans `phase1/README.md`, le contexte global dans `docs/RECAP-PHASE1.md`.

---

## 1. Se connecter au SIEM partagé (Tailscale)

**Côté moi (déjà fait / à faire) :** Tailscale installé sur le serveur Wazuh, et je vous envoie une invitation à rejoindre le réseau (tailnet). IP Tailscale du serveur : **`<je vous la communique>`** (format `100.x.x.x`).

**Côté vous :**

1. Installez Tailscale : https://tailscale.com/download (Windows/Mac/Linux), puis connectez-vous avec le compte que je vous ai invité.
2. Vérifiez que vous voyez le serveur : `ping <IP-tailscale-serveur>`.
3. Ouvrez le **dashboard Wazuh** dans votre navigateur : `https://<IP-tailscale-serveur>` (acceptez le certificat, login `admin` / je vous donne le mot de passe en privé).

À partir de là, vous voyez en temps réel les agents, les alertes, le FIM, la conformité. C'est là qu'on vérifie le résultat de tout ce qu'on fait.

> Pour ceux qui veulent brancher **leur propre machine** comme agent surveillé : suivez `agents/` du repo avec `WAZUH_MANAGER=<IP-tailscale-serveur>`.

---

## 2. Workflow commun (à respecter par tous)

- On travaille via **GitHub** : une branche par tâche, puis **Pull Request** (je relis avant de merger).
- Une **issue GitHub par tâche**, avec un responsable assigné.
- Conventions : agents nommés `srv-linux` / `ws-windows` / `srv-web`, groupes `linux` / `windows`. Règles custom : **id ≥ 100000**.
- Ne jamais committer de mots de passe / fichiers d'identifiants.

---

## 3. Rôle « Détection & Règles »

**Objectif :** écrire des règles de détection personnalisées pour les use cases du cahier des charges et les mapper à MITRE ATT&CK.

**Où ça vit :** fichier `rules/local_rules.xml` du repo → déployé sur le serveur dans `/var/ossec/etc/rules/local_rules.xml`, puis `sudo systemctl restart wazuh-manager`.

**Comment tester une règle (sans rien casser) :** l'outil `wazuh-logtest` simule un log et montre la règle déclenchée. En SSH sur le serveur (via Tailscale) :

```bash
sudo /var/ossec/bin/wazuh-logtest
# puis collez une ligne de log d'exemple
```

**Exemple de règle custom** (à mettre dans `rules/local_rules.xml`) — fait alerter un changement de configuration sur un switch Cisco (aujourd'hui il retombe sur une règle parente de niveau 0) :

```xml
<group name="local,cisco,switch,">
  <rule id="100100" level="8">
    <if_sid>4700</if_sid>
    <match>%SYS-5-CONFIG_I</match>
    <description>Switch Cisco : changement de configuration détecté</description>
    <mitre>
      <id>T1601</id>
    </mitre>
  </rule>
</group>
```

Test associé :

```
%SYS-5-CONFIG_I: Configured from console by admin on vty0
```

→ doit désormais déclencher la règle **100100, niveau 8**.

**Premières tâches (une issue / PR chacune) :**

1. Règle **brute-force SSH** (ou ajustement du seuil de la règle 5712) + test.
2. Règle **exécution de processus suspect** (s'appuyer sur la collecte `process list` déjà active sur les agents Linux).
3. Règle **switch** ci-dessus + une pour interface down (`%LINK-3-UPDOWN`) et ACL refusée (`%SEC-6-IPACCESSLOGP`).
4. Tableau **MITRE ATT&CK** : pour chaque règle, l'ID technique (ex. T1110 brute-force, T1059 exécution).

**Livrable :** `rules/local_rules.xml` complété + un doc `rules/README.md` listant chaque règle (id, niveau, description, technique MITRE) et la commande `logtest` qui la valide.

---

## 4. Rôle « Tests & Simulation »

**Objectif :** créer des scripts d'attaque **reproductibles** qui valident que la détection fonctionne, et produire un rapport de validation.

**Où ça vit :** un dossier `tests/` dans le repo. On vérifie le résultat dans le dashboard partagé (filtrer sur `agent.name` et `rule.level >= 5`) ou dans `/var/ossec/logs/alerts/alerts.log`.

**Exemples de tests à scripter :**

```bash
# tests/test-fim.sh — modifie un fichier surveillé → doit déclencher la règle 550
echo "# test $(date)" | sudo tee -a /etc/hosts

# tests/test-web.sh — attaques web → règles 31101 / 31103 / 31106
curl -s "http://localhost/page-inexistante" -o /dev/null
curl -s "http://localhost/?id=1+union+select+1,2,3--" -o /dev/null
curl -s "http://localhost/?q=<script>alert(1)</script>" -o /dev/null

# tests/test-bruteforce.sh — échecs d'authentification → règles 5503 / brute-force
for i in $(seq 1 8); do su nonexistent 2>/dev/null; done
```

**Tableau de validation à remplir (le cœur du livrable) :**

| Test | Action | Règle attendue | Observé (✅/❌) | Capture |
|---|---|---|---|---|
| FIM | modif `/etc/hosts` | 550 | | |
| Web SQLi | `union select` | 31103/31106 | | |
| Web 404 | page inexistante | 31101 | | |
| Brute-force | 8 échecs login | 5503 + brute-force | | |
| Firewall | mauvais login pfSense | 2501 | | |
| Switch | log Cisco `LOGIN_FAILED` | 4724 | | |

**Premières tâches (une issue / PR chacune) :**

1. Scripter les tests ci-dessus dans `tests/` (un script par catégorie).
2. Remplir le tableau de validation avec captures d'écran du dashboard.
3. Rédiger `tests/README.md` : comment lancer chaque test et le résultat attendu.

**Livrable :** dossier `tests/` + rapport de validation (tableau rempli + captures) — directement réutilisable dans la soutenance.

---

## 5. En résumé

1. Installez Tailscale, rejoignez le tailnet, ouvrez le dashboard.
2. Prenez une issue GitHub correspondant à votre rôle.
3. Travaillez en branche, testez (`wazuh-logtest` ou scripts), ouvrez une PR.
4. On valide ensemble le résultat dans le dashboard partagé.

Des questions ? Pingez-moi. 🚀
