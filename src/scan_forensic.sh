#!/bin/bash

# Couleurs pour la lisibilité
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Fichier de log cible 
LOG_SECURE="/var/log/secure"

# Vérification des droits root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Erreur : Ce script nécessite les droits root pour lire les logs.${NC}"
  exit 1
fi

echo "==================================================="
echo "   ANALYSE FORENSIQUE - iut-503"
echo "==================================================="
echo "Début : $(date)"
echo ""

# --- 1. Détection Brute Force SSH ---
echo -e "${YELLOW}[*] Analyse SSH (Brute Force)${NC}"

if [ -f "$LOG_SECURE" ]; then
    FAILED_IPS=$(grep "sshd" "$LOG_SECURE" 2>/dev/null | grep "Failed password" | awk '{print $(NF-3)}' | sort | uniq -c | sort -nr)
    
    if [ -n "$FAILED_IPS" ]; then
        FOUND=0
        while read -r count ip; do
            if [ "$count" -gt 3 ]; then
                echo -e "${RED}[!] $count échecs depuis $ip${NC}"
                FOUND=1
                
                # Vérifier si cette IP a réussi à se connecter ensuite
                if grep "sshd" "$LOG_SECURE" 2>/dev/null | grep "Accepted password" | grep -q "$ip"; then
                    echo -e "${RED}    >>> ALERTE CRITIQUE : Connexion réussie après échecs !${NC}"
                fi
            fi
        done <<< "$FAILED_IPS"
        
        [ $FOUND -eq 0 ] && echo -e "${GREEN}Aucune activité suspecte détectée.${NC}"
    else
        echo -e "${GREEN}Aucune tentative SSH échouée.${NC}"
    fi
else
    echo "Fichier $LOG_SECURE introuvable."
fi
echo ""

# --- 2. Détection Escalade Privilèges ---
echo -e "${YELLOW}[*] Analyse Auditd (Accès Fichiers)${NC}"

if command -v ausearch &>/dev/null; then
    AUDIT_SHADOW=$(ausearch -k tentative_shadow -i 2>/dev/null | grep "success=no")
    
    if [ -n "$AUDIT_SHADOW" ]; then
        echo -e "${RED}[!] Tentative d'accès illégal à /etc/shadow${NC}"
        # Extraction propre : on prend la première ligne pour éviter les doublons
        echo "$AUDIT_SHADOW" | head -n 1 | grep -oE 'uid=[a-zA-Z0-9_-]+|comm="[^"]+"' | tr '\n' ' '
        echo ""
    else
        echo -e "${GREEN}Aucune violation de règle auditd détectée.${NC}"
    fi
else
    echo "Auditd n'est pas installé."
fi
echo ""

# --- 3. Détection OOM Killer ---
echo -e "${YELLOW}[*] Analyse OOM Killer (Crash Mémoire)${NC}"

# Recherche dans les logs noyau 
OOM_LAST=$(journalctl -k --since "1 hour ago" 2>/dev/null | grep "Killed process" | tail -n 1)

if [ -n "$OOM_LAST" ]; then
    echo -e "${RED}[!] OOM Killer déclenché récemment${NC}"
    
    # Extraction 
    PID=$(echo "$OOM_LAST" | grep -oP 'process \K\d+')
    NOM=$(echo "$OOM_LAST" | grep -oP '\(\K[^)]+')
    RAM_KB=$(echo "$OOM_LAST" | grep -oP 'anon-rss:\K\d+')
    
    # Conversion kB vers Go 
    RAM_GB=$((RAM_KB / 1024 / 1024))
    
    echo -e "${RED}    Processus tué : $NOM (PID $PID)${NC}"
    echo -e "${RED}    Mémoire consommée : ~${RAM_GB} Go ($RAM_KB kB)${NC}"
else
    echo -e "${GREEN}Aucun crash mémoire détecté dans la dernière heure.${NC}"
fi

echo ""
echo "==================================================="
echo "Analyse terminée."