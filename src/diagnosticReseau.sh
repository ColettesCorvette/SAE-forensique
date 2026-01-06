#!/bin/bash

SCENARIO="$1"
CIBLE="${2:-google.com}"

if [ -z "$SCENARIO" ]; then
    echo "Usage: $0 <service|latence|dns|firewall> [cible]"
    exit 1
fi

echo "=== Diagnostic réseau : $SCENARIO (cible: $CIBLE) ==="
echo

case "$SCENARIO" in
    service)
        PORT=8080
        IPT="/usr/sbin/iptables"

        echo "1.Service HTTP local sur 127.0.0.1:$PORT"
        echo "    (Lancer dans un autre terminal : python3 -m http.server $PORT --bind 127.0.0.1)"
        echo

        echo "2.Test d'accès avant panne"
        if curl -s "http://127.0.0.1:$PORT" >/dev/null; then
            echo "  -> Service accessible"
        else
            echo "  -> Service déjà inaccessible"
        fi
        echo

        echo "3.Ajout d'un filtrage avec iptables"
        sudo "$IPT" -I OUTPUT -d 127.0.0.1 -p tcp --dport "$PORT" -j DROP
        echo "  -> Règle ajoutée"
        echo

        echo "4.Test d'accès après panne"
        if curl -s --max-time 3 "http://127.0.0.1:$PORT" >/dev/null; then
            echo "  -> Toujours accessible"
        else
            echo "  -> Service inaccessible depuis le client"
        fi
        echo

        echo "6.Nettoyage"
        sudo "$IPT" -D OUTPUT -d 127.0.0.1 -p tcp --dport "$PORT" -j DROP 2>/dev/null
        ;;

    latence)
        echo "1.Ping vers $CIBLE"
        ping -c 10 "$CIBLE"
        echo

        echo "2.Traceroute / mtr vers $CIBLE"
        if command -v mtr >/dev/null 2>&1; then
            mtr -r -c 10 "$CIBLE"
        elif command -v traceroute >/dev/null 2>&1; then
            traceroute "$CIBLE"
        else
            echo "  -> mtr/traceroute non installés"
        fi
        echo

        echo "3.Comparaison avec une cible proche"
        echo "   ping -c 5 192.168.1.1"
        ;;

    dns)
        echo "1.Ping par nom"
        if ping -c 3 "$CIBLE"; then
            echo "  -> Ping OK"
        else
            echo "  -> Ping KO (nom ou réseau)"
        fi
        echo

        echo "2.Résolution DNS"
        if command -v dig >/dev/null 2>&1; then
            dig "$CIBLE"
        elif command -v host >/dev/null 2>&1; then
            host "$CIBLE"
        else
            echo "  -> dig/host non installés"
        fi
        echo

        echo "3.Test avec DNS public (si dig)"
        if command -v dig >/dev/null 2>&1; then
            dig "$CIBLE" @8.8.8.8
        fi
        echo

        echo "4.Fichier /etc/resolv.conf"
        grep -E '^nameserver' /etc/resolv.conf 2>/dev/null || echo "  -> aucun nameserver"
        ;;

    firewall)
        PORT=8080
        IPT="/usr/sbin/iptables"

        echo "1.Test HTTP local sur 127.0.0.1:$PORT"
        CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT" 2>/dev/null || echo "ERR")
        echo "  -> Code HTTP : $CODE"
        echo

        echo "2.Ajout d'un blocage pare-feu"
        sudo "$IPT" -I OUTPUT -d 127.0.0.1 -p tcp --dport "$PORT" -j DROP
        echo "  -> Règle ajoutée"
        echo

        echo "3.Nouveau test HTTP"
        CODE2=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT" 2>/dev/null || echo "ERR")
        echo "  -> Code HTTP après blocage : $CODE2"
        echo

        echo "4.Commandes utiles"
        echo "   sudo $IPT -L -v -n   # règles du pare-feu"
        echo "   ss -tuln             # ports en écoute"
        echo "   # nmap -Pn -p $PORT 127.0.0.1  # optionnel"
        echo

        echo "5.Nettoyage"
        sudo "$IPT" -D OUTPUT -d 127.0.0.1 -p tcp --dport "$PORT" -j DROP 2>/dev/null
        ;;

    *)
        echo "Scénario inconnu: $SCENARIO"
        echo "Utilise: service | latence | dns | firewall"
        exit 1
        ;;
esac

