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
        echo "1.Ping vers 127.0.0.1 (latence normale)"
        ping -c 5 127.0.0.1
        echo

        echo "2.Simulation de latence locale avec tc netem"
        if [ -x /usr/sbin/tc ]; then
            echo "   -> Ajout de 500ms de délai sur l'interface lo"
            sudo /usr/sbin/tc qdisc add dev lo root netem delay 500ms
            echo

            echo "3.Ping vers 127.0.0.1 (avec latence simulée)"
            ping -c 5 127.0.0.1
            echo

            echo "4.Nettoyage de la configuration tc"
            sudo /usr/sbin/tc qdisc del dev lo root
        else
            echo "   -> tc non disponible sur ce système"
        fi
        echo
        ;;

    dns)
        RESOLV="/etc/resolv.conf"
        BACKUP="/tmp/resolv.conf.backup.$$"
        DNS_FAUX="10.255.255.1"   # IP arbitraire qui ne répond pas en DNS

        echo "1.Ping par nom (état normal)"
        if ping -c 3 "$CIBLE"; then
            echo "  -> Ping OK"
        else
            echo "  -> Ping KO"
        fi
        echo

        echo "2.Résolution DNS normale via la configuration système"
        if command -v dig >/dev/null 2>&1; then
            dig "$CIBLE"
        elif command -v host >/dev/null 2>&1; then
            host "$CIBLE"
        else
            echo "  -> dig/host non installés"
        fi
        echo

        echo "3.Sauvegarde et corruption temporaire de /etc/resolv.conf"
        if [ -r "$RESOLV" ]; then
            sudo cp "$RESOLV" "$BACKUP"
            echo "   -> Backup dans $BACKUP"
            echo "nameserver $DNS_FAUX" | sudo tee "$RESOLV" >/dev/null
            echo "   -> /etc/resolv.conf pointe maintenant vers un DNS injoignable ($DNS_FAUX)"
        else
            echo "   -> Impossible de lire $RESOLV, abandon de la simulation DNS défaillant"
            echo
            exit 1
        fi
        echo

        echo "4.Ping par nom avec DNS cassé"
        if ping -c 3 "$CIBLE"; then
            echo "  -> Ping OK"
        else
            echo "  -> Ping KO"
        fi
        echo

        echo "5.Résolution DNS locale avec DNS cassé"
        if command -v dig >/dev/null 2>&1; then
            dig "$CIBLE"
        elif command -v host >/dev/null 2>&1; then
            host "$CIBLE"
        fi
        echo

        echo "6.Test avec DNS public"
        if command -v dig >/dev/null 2>&1; then
            dig "$CIBLE" @8.8.8.8
        fi
        echo

        echo "7.Contenu de /etc/resolv.conf pendant la panne"
        grep -E '^nameserver' "$RESOLV" 2>/dev/null || echo "  -> aucun nameserver"
        echo

        echo "8.Restaurer la configuration DNS"
        if [ -f "$BACKUP" ]; then
            sudo mv "$BACKUP" "$RESOLV"
            echo "   -> /etc/resolv.conf restauré"
        else
            echo "   -> Pas de backup trouvé"
        fi
        echo
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

