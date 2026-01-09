#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "==================================================="
echo "   DIAGNOSTIC SYSTÈME - Partie 4"
echo "==================================================="
echo "Date : $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# vue globale de l'utilisation CPU/mémoire/disques.
echo -e "${YELLOW}[*] vmstat${NC}"
vmstat 1 2
echo ""

echo -e "${YELLOW}[*] iostat${NC}"
iostat -xz 1 2
echo ""

echo -e "${YELLOW}[*] mpstat${NC}"
mpstat -P ALL 1 1 2>/dev/null || echo "  (mpstat non disponible)" # affiche tout les CPU 
echo ""

# permet d'identifier les processus gourmands, qui écrivent/lisent beaucoup sur le disque
echo -e "${YELLOW}[*] iotop / ps${NC}"
if command -v iotop >/dev/null 2>&1; then
    iotop -b -n 1 -o 2>/dev/null || echo "  (iotop disponible mais aucune activité)"
else
    echo "iotop non installé, affichage des processus par mémoire :"
    ps aux --sort=-%mem | head -8
fi
echo ""

# donne les stats CPU dans le temps
echo -e "${YELLOW}[*] sar${NC}"
sar 1 3 2>/dev/null || echo "  (sar non disponible)" # affiche les stats CPU toutes les 1 secondes, 3 fois
echo ""

# regarde les 10 derniers messages du noyau
echo -e "${YELLOW}[*] dmesg${NC}"
dmesg 2>/dev/null | tail -10 || echo "  (Aucun message noyau accessible)"
echo ""

# repérer les services lents 
echo -e "${YELLOW}[*] systemd-analyze${NC}"
systemd-analyze time 2>/dev/null || echo "  (systemd-analyze non disponible)" # donne le temps de boot 
echo "services lents :"
systemd-analyze blame 2>/dev/null | head -10 || echo "  (systemd-analyze blame non disponible)" # liste les unités triés par temps de démarrage
echo ""

echo "==================================================="
echo "Diagnostic terminé."
echo "==================================================="

