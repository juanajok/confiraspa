#!/bin/sh

# Script Name: backup_rsync.sh
# Description: Script para realizar copias de seguridad usando rsync
# Author: Juan José Hipólito
# Version: 1.1.0
# Date: 2023-03-30
# License: GNU
# Usage: Ejecuta el script manualmente o programa su ejecución en crontab
# Dependencies: rsync
# Notes: Asegúrate de que las rutas de origen y destino estén montadas antes de ejecutar este script

# Rutas de origen y destino para la copia de seguridad
declare -A backup_paths
backup_paths=(
  ["/media/WDElements/Fotos"]="/media/Backup/Fotos"
  ["/media/WDElements/Libros/Biblioteca de Calibre"]="/media/Backup/Biblioteca de Calibre"
  ["/media/WDElements/Tebeos"]="/media/Backup/Tebeos"
)

rsync_backup() {
    echo "Iniciando copias de seguridad con rsync..."

    for source in "${!backup_paths[@]}"; do
        destination=${backup_paths[$source]}
        echo "Copia de seguridad en curso: $source -> $destination"
        rsync --progress -avzh "$source" "$destination"
    done

    echo "Copias de seguridad completadas."
}

main() {
    rsync_backup
}

main
