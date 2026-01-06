# SAE-forensique

---

# Partie 1 - États de processus

Programme C pour simuler et analyser différents états de processus sous Linux : R (running), S (sleeping), D (disk sleep), Z (zombie) et T (stopped).

## Compilation et Utilisation

```bash
make                 # Compiler
./processus <1-5>    # Exécuter
make clean           # Nettoyer
```

**Options :**
- `1` - Boucle CPU infinie (État R)
- `2` - Fuite mémoire progressive (État S)  
- `3` - Blocage I/O pendant 15s (État D)
- `4` - Processus zombie (État Z)
- `5` - Processus stoppé (État T)

---

## Méthodologie de diagnostic

### État R - CPU à 100%
**Symptômes :** Système ralenti, CPU à 100%

```bash
# Identifier
ps aux --sort=-%cpu | head -10
top -o %CPU

# Analyser
ps aux | grep processus  # STAT = R
top -p <PID>

# Résoudre
kill <PID>
```

### État S - Fuite mémoire
**Symptômes :** Mémoire augmente, swap utilisé

```bash
# Identifier
ps aux --sort=-%mem | head -10
top -o %MEM

# Surveiller
watch -n 1 "ps aux | grep processus | grep -v grep"
cat /proc/<PID>/status | grep VmRSS

# Résoudre
kill <PID>
```

### État D - Blocage I/O
**Symptômes :** Processus figé, impossible à tuer

```bash
# Identifier
ps aux | grep " D"

# Analyser
ps -p <PID> -o pid,stat,wchan,cmd
cat /proc/<PID>/stack

# Résoudre
# ATTENDRE - kill -9 ne fonctionne PAS sur état D
```

### État Z - Zombie
**Symptômes :** Processus `<defunct>`, pas de ressources

```bash
# Identifier
ps aux | grep defunct

# Trouver le parent
ps -o ppid= -p <PID_zombie>

# Résoudre
kill <PPID>  # Tuer le parent
```

### État T - Stoppé
**Symptômes :** Processus gelé mais vivant

```bash
# Identifier
ps aux | grep " T"

# Reprendre
kill -CONT <PID>

# Ou tuer
kill -9 <PID>
```

---
## Commandes essentielles

```bash
# Surveillance
top / htop
watch -n 1 "ps aux | grep processus"

# Détails processus
ps aux | grep <nom>
ps -p <PID> -o pid,stat,%cpu,%mem,cmd
cat /proc/<PID>/status

# Signaux
kill <PID>        # SIGTERM (15)
kill -9 <PID>     # SIGKILL (9)
kill -CONT <PID>  # Reprendre (18)
kill -STOP <PID>  # Stopper (19)
```

---

## États des processus (STAT)

- **R** (running) : En cours d'exécution
- **S** (sleeping) : En attente d'événement
- **D** (disk sleep) : Attente I/O (non interruptible)
- **Z** (zombie) : Terminé, en attente de nettoyage
- **T** (stopped) : En pause

---

## Analyse forensique avancée

### 1. Repérage rapide

```bash
pidof processus              # Juste le PID
pgrep -a processus           # PID + commande complète (ex: "17316 ./processus 3")
```

### 2. Format personnalisé avec wchan

**`wchan`** (Waiting Channel) = fonction noyau où le processus est bloqué

```bash
ps -eo pid,ppid,stat,wchan:20,cmd --sort=state

# Exemples de wchan :
# - do_vfork      → État D (vfork bloquant)
# - hrtimer_nanosleep → État S (sleep/usleep)
# - do_wait       → Parent attend un enfant
```

### 3. Arbre de filiation avec pstree

```bash
pstree -p -s $(pidof processus)

# Montre :
# - Zombie attaché au parent avec <defunct>
# - Relation parent/enfant en état D (vfork)
```

### 4. Analyse via /proc (la source brute)

```bash
# État détaillé
cat /proc/<PID>/status | grep State
# Ex: State: D (disk sleep)

# Cause du blocage
cat /proc/<PID>/wchan
# Ex: do_vfork, hrtimer_nanosleep

# Pile d'appels noyau (état D)
cat /proc/<PID>/stack
```

### 5. Traçage avec strace

**Ne fonctionne PAS sur processus en état D ou Z**

#### Exemple 1 : Fuite mémoire (État S)
```bash
./processus 2 &
sudo strace -p $(pidof processus)

# Sortie attendue (boucle infinie) :
# nanosleep({tv_sec=0, tv_nsec=50000000}, NULL) = 0
# mmap(NULL, 1048576, ...) = 0x7f...    ← malloc
# memset(0x7f..., 0, 1048576)           ← force l'allocation
```
**Preuve :** Allocations `mmap` sans `munmap` (pas de libération)

#### Exemple 2 : Zombie (État Z)
```bash
./processus 4 &
PPID=$(ps -o ppid= -p $(pgrep -x processus | tail -1))
sudo strace -p $PPID

# Sortie attendue :
# nanosleep({tv_sec=20, ...})
# --- SIGCHLD {si_signo=SIGCHLD, si_code=CLD_EXITED} ---
```
**Preuve :** Parent reçoit `SIGCHLD` mais ignore (pas de `wait()`)

#### Exemple 3 : Blocage I/O (État D)
```bash
# Lancer AVANT que le processus bloque :
sudo strace ./processus 3

# Dernières lignes avant blocage :
# clone(...) = <PID_enfant>      ← vfork()
# [Processus figé, strace aussi]
```

### 6. Surveillance continue avec htop

```bash
htop
# Touches utiles :
# - F4 : Filtrer par "processus"
# - F5 : Vue arborescente (voir parent/enfant)
# - Sélectionner + s : Lancer strace direct
# - F10 : Quitter
```

### Méthodologie optimale 

1. **Repérer :** `pgrep -a processus`
2. **Visualiser :** `htop` (consommation) ou `pstree -p` (hiérarchie)
3. **Comprendre le blocage :** `cat /proc/<PID>/wchan`
4. **Prouver l'activité :** `sudo strace -p <PID>` (sauf D/Z)

### Script Ruby - Rapport d'analyse automatisé

Le script `analyse_processus.rb` génère un rapport complet sur n'importe quel processus.

### Utilisation

```bash
ruby analyse_processus.rb <PID>
```

### Que fait le script ?

Le script lit directement les fichiers `/proc/<PID>/*` pour extraire :

1. **Informations de base** : nom du processus, commande complète, état (R/S/D/Z/T)
2. **Consommation ressources** : 
   - CPU : temps total d'exécution en secondes
   - Mémoire : taille virtuelle (VmSize) et résidente (VmRSS) en MB
3. **Fichiers ouverts** : liste des 10 premiers descripteurs de fichiers (FD) avec leurs chemins
4. **Appels système récents** : capture via `strace` pendant 1 seconde (nécessite root)

### Exemple avec le processus de fuite mémoire

```bash
# Lancer une fuite mémoire
./processus 2 &

# Analyser (le PID s'affiche au démarrage)
ruby analyse_processus.rb 12345
```

**Sortie attendue :**
```
═══ RAPPORT PROCESSUS PID 12345 ═══

Nom: processus
Commande: ./processus 2
État: S (Sleeping)

CPU: 0.15s
Mémoire virtuelle: 245 MB
Mémoire résidente: 187 MB    

Fichiers ouverts (3):
  • /dev/pts/0
  • /lib/x86_64-linux-gnu/libc.so.6
  • /usr/lib/locale/locale-archive

Appels système récents:
  • nanosleep    ← usleep(50000)
  • mmap         ← malloc(1MB)
  • memset       ← Force l'allocation
```


---

# Partie 2 - Diagnostic réseau

## Script diagnosticReseau.sh - Diagnostic de pannes réseau

Le script `diagnosticReseau.sh` permet de simuler et diagnostiquer différents types de problèmes réseau courants.

### Utilisation

```bash
bash src/diagnosticReseau.sh <scenario> [cible]
```

**Scénarios disponibles :**
- `service` - Test de blocage de service HTTP local
- `latence` - Analyse de latence réseau
- `dns` - Diagnostic de résolution DNS
- `firewall` - Vérification de règles pare-feu

**Cible :** Par défaut `google.com`, personnalisable

### 1. Scénario `service` - Service inaccessible

Simule un blocage de service HTTP local avec iptables :

```bash
# Lancer d'abord un serveur HTTP dans un terminal :
python3 -m http.server 8080 --bind 127.0.0.1

# Dans un autre terminal :
bash src/diagnosticReseau.sh service
```

**Étapes du diagnostic :**
1. Test d'accès au service avant panne
2. Ajout d'une règle iptables bloquant le port 8080
3. Test d'accès après blocage (échec attendu)
4. Nettoyage automatique de la règle

**Commandes utiles affichées :**
- `sudo iptables -L -v -n` : Lister les règles du pare-feu
- `ss -tuln` : Voir les ports en écoute

### 2. Scénario `latence` - Problème de lenteur

Analyse la latence réseau vers une cible :

```bash
bash src/diagnosticReseau.sh latence google.com
```

**Tests effectués :**
1. Ping classique (10 paquets) vers la cible
2. Traceroute/mtr pour identifier les sauts réseau
3. Suggestion de comparaison avec une cible proche (gateway)

**Outils utilisés :** `ping`, `mtr`, `traceroute`

### 3. Scénario `dns` - Problème de résolution DNS

Diagnostique les problèmes de résolution de noms de domaine :

```bash
bash src/diagnosticReseau.sh dns google.com
```

**Tests effectués :**
1. Ping par nom (test combiné résolution + connectivité)
2. Résolution DNS avec `dig` ou `host`
3. Test avec DNS public (8.8.8.8) pour comparaison
4. Vérification du fichier `/etc/resolv.conf`

**Permet de distinguer :** Problème DNS vs problème réseau

### 4. Scénario `firewall` - Blocage pare-feu

Teste le blocage d'un service par le pare-feu :

```bash
# Lancer d'abord un serveur HTTP :
python3 -m http.server 8080 --bind 127.0.0.1

# Tester :
bash src/diagnosticReseau.sh firewall
```

**Tests effectués :**
1. Test HTTP initial (récupère le code HTTP)
2. Ajout d'une règle iptables de blocage
3. Nouveau test HTTP (échec attendu)
4. Affichage des commandes de diagnostic
5. Nettoyage automatique

### Prérequis système

Le script détecte automatiquement les outils disponibles :
- **Obligatoires :** `curl`, `ping`, `iptables` (avec sudo)
- **Optionnels :** `dig`, `host`, `mtr`, `traceroute`

### Exemple de rapport complet

```bash
bash src/diagnosticReseau.sh dns example.com

# Sortie attendue :
# === Diagnostic réseau : dns (cible: example.com) ===
#
# 1.Ping par nom
# PING example.com (93.184.216.34)...
#   -> Ping OK
#
# 2.Résolution DNS
# example.com.    3600    IN      A       93.184.216.34
#
# 3.Test avec DNS public (si dig)
# ;; SERVER: 8.8.8.8#53
#
# 4.Fichier /etc/resolv.conf
# nameserver 192.168.1.1
```

---

