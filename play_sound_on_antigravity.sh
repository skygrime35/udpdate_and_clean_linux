#!/bin/bash

# On attend 30 secondes au démarrage pour être sûr que le système audio est prêt
sleep 30

last_time=0

# Lancement de la surveillance
dbus-monitor "interface='org.freedesktop.Notifications'" | \
grep --line-buffered 'string "Antigravity"' | \
while read -r line; do
    # Heure actuelle
    current_time=$(date +%s)

    # Calcul de la différence
    diff=$((current_time - last_time))

    # Si plus de 2 secondes d'écart
    if [ $diff -ge 2 ]; then
        paplay /usr/share/sounds/freedesktop/stereo/message.oga &
        last_time=$current_time
    fi
done
