# SAE 3.03 - Analyse Forensique et Débogage Système

Outils et méthodologies pour le diagnostic de processus, l'analyse réseau et l'investigation forensique sous Linux.

**Groupe :** Fuchs, Hary, Schouver | **Date :** Janvier 2026

---

## Préparation

```bash
make              # Compiler le simulateur
./processus <1-5> # Exécuter (voir options ci-dessous)
make clean        # Nettoyer
```

---

## 1. Analyse de Processus

### Simulateur d'états (`processus.c`)

Génère 5 états processus différents pour entraînement au diagnostic.

| Option | État | Symptôme principal | Commandes clés |
|--------|------|-------------------|----------------|
| `./processus 1` | **R** (Running) | CPU 100%, système ralenti | `top -o %CPU`, `ps aux --sort=-%cpu` |
| `./processus 2` | **S** (Sleeping) | RAM augmente progressivement | `htop` (RES), `watch "ps aux \| grep processus"` |
| `./processus 3` | **D** (Disk sleep) | Impossible à tuer, load avg élevé | `ps -eo wchan`, `cat /proc/<PID>/stack` |
| `./processus 4` | **Z** (Zombie) | `<defunct>`, table PID saturée | `pstree -p`, `ps -o ppid=` (tuer parent) |
| `./processus 5` | **T** (Stopped) | Processus suspendu | `kill -CONT <PID>` pour reprendre |

**Outils de diagnostic avancés :**

```bash
# Repérage rapide
pgrep -a processus              # PID + commande complète
pidof processus                 # Juste le PID

# Analyse blocage (état D)
cat /proc/<PID>/wchan           # Fonction noyau bloquante
cat /proc/<PID>/stack           # Pile d'appels kernel

# Traçage système (états S/R uniquement)
sudo strace -p <PID>            # Appels système en temps réel
sudo strace -c ./processus 2    # Statistiques d'exécution

# Visualisation hiérarchique
pstree -p -s $(pidof processus) # Arbre parent/enfant
```

### Script Ruby (`analyse_processus.rb`)

Génère un rapport automatisé sur n'importe quel processus (lecture `/proc`, strace).

**Utilisation :**
```bash
ruby src/analyse_processus.rb <PID>
```

**Informations extraites :**
- État actuel (R/S/D/Z/T) et commande complète
- Consommation CPU/RAM (VmSize, VmRSS)
- Fichiers ouverts (descripteurs `/proc/<PID>/fd`)
- Appels système récents (via `strace` temporaire)

**Exemple de sortie :**
```
═══ RAPPORT PROCESSUS PID 12345 ═══
Nom: processus | Commande: ./processus 2 | État: S (Sleeping)
CPU: 0.15s | RAM: 187 MB (résidente)
Fichiers: /dev/pts/0, libc.so.6
Syscalls: nanosleep, mmap, memset (fuite détectée)
```


---

## 2. Diagnostic Réseau

### Script `diagnosticReseau.sh`

Automatise la détection de pannes réseau courantes.

**Utilisation :**
```bash
bash src/diagnosticReseau.sh <scenario> [cible]
```

| Scénario | Description | Commandes utilisées |
|----------|-------------|---------------------|
| `service` | Test d'accessibilité port local (simule blocage firewall) | `curl`, `ss -tuln`, `iptables -L` |
| `latence` | Analyse qualité réseau et route | `ping`, `mtr`, `traceroute` |
| `dns` | Chaîne de résolution DNS (DNS vs Réseau) | `dig`, `host`, `/etc/resolv.conf` |
| `firewall` | Vérification règles de filtrage | `iptables -L -v -n`, `curl` |

**Exemples d'utilisation :**

```bash
# Tester un service HTTP local
python3 -m http.server 8080 --bind 127.0.0.1 &
bash src/diagnosticReseau.sh service

# Analyser la latence vers Google
bash src/diagnosticReseau.sh latence google.com

# Diagnostiquer un problème DNS
bash src/diagnosticReseau.sh dns example.com

# Vérifier le pare-feu
bash src/diagnosticReseau.sh firewall
```

**Fonctionnalités :**
- Détection automatique des outils disponibles
- Simulation de pannes (ajout/suppression de règles iptables)
- Nettoyage automatique après test
- Suggestions de commandes pour approfondir le diagnostic

---

## 3. Investigation Forensique

Analyse post-mortem de deux incidents de sécurité réels.

### Incident A : Brute Force SSH + Escalade de Privilèges

**Contexte :** 15 tentatives SSH échouées suivies d'une connexion réussie et tentative d'accès à `/etc/shadow`.

**Détection :**

```bash
# Connexions échouées
sudo lastb -n 15

# Connexions réussies
last -n 5 | grep pts

# Logs SSH
sudo journalctl -u sshd --since "07:00" --until "12:00" -p warning

# Tentative d'escalade (Audit)
sudo ausearch -f /etc/shadow -ts 07/01/2026 11:00:00 -i
```

**Preuve clé (Audit log) :**
```
type=SYSCALL comm="cat" exe="/usr/bin/cat" name="/etc/shadow" 
success=no exit=-13 (EACCES) UID="iut-503"
```

**Chronologie :**
- **10:51-11:11** : 15 échecs de connexion (127.0.0.1)
- **11:05:20** : Connexion réussie (mot de passe faible)
- **11:12:34** : `cat /etc/shadow` → BLOQUÉ par SELinux

**Correctifs appliqués :**
```bash
# Bloquer le compte
sudo passwd -l iut-503

# Installer Fail2ban
sudo dnf install fail2ban
sudo systemctl enable --now fail2ban

# Durcir SSH (/etc/ssh/sshd_config)
MaxAuthTries 3
PermitRootLogin no
PasswordAuthentication no  # Forcer les clés SSH
```

---

### Incident B : Saturation Mémoire

**Contexte :** 4 crashs successifs en 8 minutes causés par le processus `./processus` (option 2 - fuite mémoire).

**Détection :**

```bash
# Logs OOM Killer
sudo dmesg -T | grep -i "killed process"
sudo journalctl -k -r | grep "Out of memory"

# Historique des commandes
sudo cat ~iut-503/.bash_history | grep processus
```

**Preuve (Kernel log) :**
```
janv. 07 15:25:25 iutnc-503-09 kernel: Out of memory: Killed process 15989 (processus) 
total-vm:21740520kB, anon-rss:14814912kB (14.8 Go RAM)
```

**Chronologie :**

| Heure | PID | RAM (RSS) | Action |
|-------|-----|-----------|--------|
| 15:17:59 | 15608 | 14.5 Go | OOM Kill |
| 15:22:14 | 15810 | 14.8 Go | OOM Kill |
| 15:23:18 | 15825 | 14.8 Go | OOM Kill |
| 15:25:25 | 15989 | 14.8 Go | OOM Kill |

**Correctifs appliqués :**

```bash
# 1. Limites mémoire par utilisateur
# /etc/systemd/logind.conf
echo "UserMemoryMax=2G" >> /etc/systemd/logind.conf
sudo systemctl restart systemd-logind

# 2. Limites ulimit
# /etc/security/limits.conf
echo "iut-503  hard  as  2000000" >> /etc/security/limits.conf

# 3. Surveillance RAM
watch -n 1 'ps aux --sort=-%mem | head -10'

# 4. Protection services critiques
mkdir -p /etc/systemd/system/sshd.service.d/
echo -e "[Service]\nOOMScoreAdjust=-900" > /etc/systemd/system/sshd.service.d/oom.conf
sudo systemctl daemon-reload
```

---

## 4. Outils Forensiques Essentiels

### Analyse de logs système

```bash
# Authentifications
sudo journalctl -u sshd --since today
sudo last -n 10           # Connexions réussies
sudo lastb -n 10          # Connexions échouées
sudo lastlog | grep -v Never

# Kernel (OOM, crashs)
sudo dmesg -T
sudo journalctl -k --since "1 hour ago"

# Audit (fichiers sensibles)
sudo ausearch -f /etc/shadow -i
sudo ausearch -f /etc/passwd -i
sudo aureport --summary
```

### Surveillance temps réel

```bash
# Processus actifs
htop
top -o %MEM
watch -n 1 'ps aux --sort=-%cpu | head -5'

# Réseau
ss -tuln              # Ports en écoute
netstat -antp         # Connexions actives
iftop                 # Bande passante

# Mémoire
free -h
vmstat 1
cat /proc/meminfo
```

---

## Structure du Projet

```
SAE-forensique/
├── Makefile                     # Compilation
├── README.md                    # Documentation complète
├── processus                    # Binaire compilé
└── src/
    ├── processus.c              # Code source simulateur (Partie 1)
    ├── analyse_processus.rb     # Script Ruby analyse (Partie 1)
    ├── diagnosticReseau.sh      # Script Bash diagnostic réseau (Partie 2)
    ├── diagnosticSysteme.sh     # Script Bash diagnostic système
    └── scan_forensic.sh         # Script analyse forensique (Partie 3)
```

---

## Méthodologie Complète (Synthèse)

**Diagnostic processus :**
1. Repérer : `pgrep -a <nom>`
2. Visualiser : `htop` ou `ps aux --sort=-%mem`
3. Analyser : `cat /proc/<PID>/status`, `strace -p <PID>`
4. Résoudre : `kill`, `kill -9`, ou tuer le parent (zombies)

**Diagnostic réseau :**
1. Tester connectivité : `ping <cible>`
2. Analyser route : `mtr <cible>`
3. Vérifier DNS : `dig <domaine>`
4. Inspecter firewall : `iptables -L -v -n`

**Investigation forensique :**
1. Logs d'authentification : `lastb`, `journalctl -u sshd`
2. Logs noyau : `dmesg -T`, `journalctl -k`
3. Audit : `ausearch -f <fichier>`, `aureport`
4. Corrélation : Croiser dates/heures entre sources

---
