#!/bin/sh

# Script Name: backup_rsync.sh
# Description: Script para realizar copias de seguridad usando rsync
# Author: Juan José Hipólito
# Version: 1.1.0
# Date: 2023-03-30
# License: GNU
# Usage: Ejecuta el script manualmente o programa su ejecución en crontab
# Dependencies: rsync y  jq (https://stedolan.github.io/jq/)
# Notes: Asegúrate de que las rutas de origen y destino estén montadas antes de ejecutar este script

SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="$SCRIPT_DIR/backup_rsync_config.json"

echo "Script directory: $SCRIPT_DIR"
echo "Config file: $CONFIG_FILE"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file not found"
    exit 1
fi

directorios=$(jq -c '.directorios[]' $CONFIG_FILE)

echo "Directorios:"
echo "$directorios"

# Ejecutar rsync para cada par de directorios origen y destino
echo "$directorios" | while read -r dir_info; do
    origen=$(echo $dir_info | jq -r '.origen')
    destino=$(echo $dir_info | jq -r '.destino')
    echo "Origen: $origen"
    echo "Destino: $destino"
    rsync --progress -avzh "$origen" "$destino"
done
