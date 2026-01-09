#!/bin/bash

NUM_CORES=$(nproc) # donne le nombre de coeurs

# fonction qui permet d'arrêter proprement les jobs en arrière plan
cleanup() {
    echo ""
    echo "Arrêt du scénario..."
    kill %1 %2 %3 %4 %5 %6 %7 %8 %9 %10 2>/dev/null
    exit 0
}

trap cleanup SIGINT

echo "==================================================="
echo "   SCÉNARIO CPU - Charge système"
echo "==================================================="
echo "Nombre de cœurs : $NUM_CORES"
echo "Lancement de $NUM_CORES boucles infinies..."
echo ""
echo "Ctrl+C pour arrêter."
echo "==================================================="
echo ""

# Boucle infinie
for ((i = 0; i < NUM_CORES; i++)); do
    while true; do :; done & # opération vide 
done

wait

