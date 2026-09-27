#!/bin/bash

# Couleurs (optionnel, pour un affichage plus joli)
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Rapport système ===${NC}"

# Date et heure
echo "Date       : $(date '+%d/%m/%Y %H:%M')"

# Uptime (en format lisible)
uptime_info=$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | cut -d',' -f1)
echo "Uptime     : $uptime_info"

# Utilisation mémoire
mem_info=$(free -h | awk 'NR==2 {print $3 " / " $2}')
echo "Mémoire    : $mem_info"

# Espace disque de la partition racine (/)
disk_usage=$(df -h / | awk 'NR==2 {print $5}')
echo "Disque /   : $disk_usage"

# Utilisation CPU approximative (moyenne sur 1 minute)
cpu_load=$(uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | xargs)
echo "Charge CPU : $cpu_load (load average 1 min)"

echo
echo "Rapport généré avec succès."