# Guide de démonstration — lancer des attaques & vérifier la détection

Ce guide permet à n'importe qui (coéquipier, jury) de **provoquer une anomalie / une attaque** et de **vérifier que le SIEM Wazuh la détecte**, en quelques commandes. Idéal pour les tests et pour la soutenance en direct.

> Toutes les attaques ci-dessous sont **inoffensives** : ce sont des simulations destinées à déclencher les règles de détection. On nettoie derrière quand c'est nécessaire.

---

## 0. Préparation (avant la démo)

1. Vérifier que les agents sont connectés — **sur le serveur** :

   ```bash
   sudo /var/ossec/bin/agent_control -ls
   ```

   `srv-linux` et `ws-windows` doivent être **Active**.

2. Ouvrir le **dashboard** : `https://192.168.195.134` (ou l'IP de votre serveur), aller dans le module **Threat Hunting** (ou *Security events*).
3. (Recommandé pour la démo live) garder un terminal serveur avec les alertes qui défilent :

   ```bash
   sudo tail -f /var/ossec/logs/alerts/alerts.log
   ```

> **Astuce soutenance :** lancez chaque test **une fois avant** le public (pour que les fichiers soient « connus » du FIM et que tout soit chaud), gardez le `tail -f` visible sur un écran, et prévoyez une **vidéo de secours** de la démo.

---

## Comment vérifier une alerte (2 méthodes)

- **Dashboard** → *Threat Hunting* → barre de recherche, filtrer par exemple :
  - `rule.id: 550` (une règle précise)
  - `rule.groups: web` (une catégorie)
  - `agent.name: srv-linux`
  - `rule.level >= 5` (ne garder que le significatif)
- **Terminal serveur** :

  ```bash
  sudo tail -f /var/ossec/logs/alerts/alerts.log
  ```

---

## Tableau récapitulatif

| # | Scénario | Où lancer | Règle attendue | Filtre dashboard |
|---|---|---|---|---|
| 1 | Modification fichier système (FIM) | srv-linux | **550** | `rule.id: 550` |
| 2 | Attaque web (scan + SQLi + XSS) | srv-linux | **31101 / 31103 / 31106** | `rule.groups: web` |
| 3 | Force brute / login échoué | ws-windows | groupe `authentication_failed` (ex. **60122**) | `agent.name: ws-windows AND rule.groups: authentication_failed` |
| 4 | Accès non autorisé au firewall | GUI pfSense | **2501** | `rule.id: 2501` |
| 5 | Échec de connexion switch | serveur (logtest) | **4724** | (logtest) |

---

## 1. Modification d'un fichier système (FIM)

**Ce qu'on démontre :** la détection en temps réel d'une modification non autorisée d'un fichier sensible (surveillance d'intégrité).

**Où :** sur la VM `srv-linux`.

**Commande (l'attaque) :**

```bash
echo "192.168.1.66  banque-frauduleuse.com  # demo-fim" | sudo tee -a /etc/hosts
```

**Résultat attendu (~10 s) :** règle **550** *« Integrity checksum changed »*, agent `srv-linux`.

**Où vérifier :** Dashboard → *Threat Hunting* → `rule.id: 550`. Ou terminal :

```bash
sudo grep "Integrity checksum" /var/ossec/logs/alerts/alerts.log | tail
```

**Nettoyage :**

```bash
sudo sed -i '/demo-fim/d' /etc/hosts
```

**À dire en présentation :** *« Un attaquant ajoute une entrée dans /etc/hosts pour rediriger un site bancaire vers un serveur pirate. Le FIM détecte la modification en temps réel et remonte l'ancienne et la nouvelle empreinte du fichier. »*

---

## 2. Attaque web (scan, injection SQL, XSS)

**Ce qu'on démontre :** la détection d'attaques applicatives sur le serveur web.

**Où :** sur `srv-linux` (le serveur Apache tourne dessus).

**Commandes (les attaques) :**

```bash
curl -s "http://localhost/page-qui-nexiste-pas" -o /dev/null                       # scan / 404
curl -s "http://localhost/?id=1+union+select+user,password+from+users--" -o /dev/null   # injection SQL
curl -s "http://localhost/?q=<script>alert('xss')</script>" -o /dev/null            # XSS
curl -s "http://localhost/?file=../../../../etc/passwd" -o /dev/null                # traversée de répertoire
```

**Résultat attendu :** règles **31101** (erreur 4xx), **31103** (injection SQL), **31106** (attaque web ayant répondu 200).

**Où vérifier :** Dashboard → `rule.groups: web`. Ou terminal :

```bash
sudo grep -E "SQL injection|web attack|Web server 400" /var/ossec/logs/alerts/alerts.log | tail
```

**À dire en présentation :** *« On simule un scan puis une injection SQL et une XSS. Wazuh reconnaît les signatures d'attaque web ; l'alerte 31106 “returned code 200” est même critique, car elle signale que le serveur a répondu OK à une requête malveillante. »*

---

## 3. Force brute / tentative de connexion (Windows)

**Ce qu'on démontre :** la détection de tentatives d'authentification échouées (base d'une attaque par force brute).

**Où :** sur la VM `ws-windows`.

**Action (l'attaque) :** verrouiller la session (**Win + L**) puis taper **5–6 fois un mauvais mot de passe**.

**Résultat attendu :** événements Windows **4625** (échec de connexion) → règle Wazuh du groupe `authentication_failed` (ex. **60122**) ; au-delà du seuil, une alerte de tentatives multiples.

**Où vérifier :** Dashboard → `agent.name: ws-windows AND rule.groups: authentication_failed`.

**Variante Linux** (sur `srv-linux`) : lancer `su - root` et taper un mauvais mot de passe plusieurs fois → règles du groupe `authentication_failed` (ex. 5503).

**À dire en présentation :** *« Un attaquant essaie plusieurs mots de passe sur un poste. Chaque échec est journalisé, et Wazuh corrèle les tentatives répétées comme une possible force brute. »*

---

## 4. Accès non autorisé au firewall (pfSense, agentless)

**Ce qu'on démontre :** la surveillance d'un équipement **sans agent**, via syslog.

**Où :** sur la **page de login du GUI pfSense**.

**Action (l'attaque) :** entrer **2–3 fois un mauvais mot de passe** admin.

**Résultat attendu :** règle **2501** *« syslog: User authentication failure »*, source = IP du pfSense.

**Où vérifier :** Dashboard → `rule.id: 2501`. Ou terminal :

```bash
sudo grep "webConfigurator authentication" /var/ossec/logs/alerts/alerts.log | tail
```

**À dire en présentation :** *« Le firewall n'a pas d'agent : il envoie ses logs en syslog. Une tentative d'accès non autorisée à son interface d'administration remonte quand même dans le SIEM. »*

---

## 5. Événement de sécurité sur un switch (Cisco, agentless)

**Ce qu'on démontre :** que Wazuh décode nativement les logs d'un switch/routeur Cisco.

**Où :** sur le **serveur** (méthode la plus fiable pour la démo).

**Commande :**

```bash
sudo /var/ossec/bin/wazuh-logtest
```

Puis coller cette ligne (Entrée) :

```
%SEC_LOGIN-4-LOGIN_FAILED: Login failed [user: admin] [Source: 192.168.1.50] [localport: 22] [Reason: Login Authentication Failed]
```

**Résultat attendu :** décodeur `cisco-ios`, règle **4724** *« Cisco IOS: Failed login to the router »*, **niveau 9**, avec tags de conformité.

**À dire en présentation :** *« Même un switch réseau, via syslog, est compris par Wazuh : ici une tentative de connexion échouée sur l'équipement est décodée et classée en niveau 9. »*

---

## Bonus — montrer la conformité (GDPR / PCI / MITRE)

Sur n'importe quelle alerte du dashboard, dépliez les détails : on y voit les tags **`gdpr`, `pci_dss`, `hipaa`, `nist`** et le mapping **MITRE ATT&CK**. Les modules dédiés *Compliance* et *MITRE ATT&CK* du dashboard offrent des vues d'ensemble. Excellent pour conclure la démo sur l'aspect réglementaire.

---

## Dépannage rapide (si une alerte ne remonte pas)

- **Rien ne s'affiche :** l'agent concerné est-il **Active** (`agent_control -ls`) ? Le manager tourne-t-il (`sudo /var/ossec/bin/wazuh-control status`) ?
- **FIM sans alerte :** modifier un fichier **existant** (déjà dans la base FIM). Créer puis supprimer un fichier neuf trop vite ne déclenche rien (les nouveaux fichiers ne sont pas alertés par défaut).
- **Web sans alerte :** vérifier qu'Apache journalise bien (`sudo tail /var/log/apache2/access.log`) et que l'agent lit ce fichier.
- **L'agent lit chaque ligne une seule fois :** si le manager était planté au moment du test, relancez l'attaque une fois le manager reparti.
- **Décalage d'horloge / certificats :** vérifier l'heure de la VM (`timedatectl`).

---

## En résumé (démo minute)

1. `agent_control -ls` → agents Active.
2. `tail -f` des alertes sur un écran, dashboard sur l'autre.
3. Scénario 1 (FIM) → 2 (web) → 4 (firewall) : les plus visuels.
4. Conclure sur les tags de conformité GDPR/MITRE d'une alerte.
