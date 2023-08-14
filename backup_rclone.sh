#!/bin/bash

# Script Name: backup_rclone.sh
# Description: Script para realizar copias de seguridad de la nube usando rclone
# Author: Juan José Hipólito
# Version: 1.2.0
# Date: 2023-08-03
# License: GNU
# Usage: Ejecuta el script manualmente o programa su ejecución en crontab
# Dependencies: rclone y jq (https://stedolan.github.io/jq/)
# Notes: Asegúrate de que las rutas de origen y destino estén montadas antes de ejecutar este script

# Variables
SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="$SCRIPT_DIR/backup_rclone_config.json"
LOG_FILE="$SCRIPT_DIR/backup_rclone.log"

# Funciones
log_message() {
    local message="$1"
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# Comenzar
log_message "Iniciando el proceso de copia de seguridad con rclone..."

# Verificar la existencia del archivo de configuración
if [ ! -f "$CONFIG_FILE" ]; then
    log_message "Archivo de configuración no encontrado."
    exit 1
fi

# Leer el archivo JSON con las rutas de las carpetas y ejecutar rclone para cada par de directorios origen y destino
jq -c '.directorios[]' "$CONFIG_FILE" | while read -r dir_info; do
    origen=$(echo "$dir_info" | jq -r '.origen')
    destino=$(echo "$dir_info" | jq -r '.destino')
    log_message "Sincronizando origen: $origen con destino: $destino..."
    rclone sync "$origen" "$destino" >> "$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        log_message "Sincronización completada para origen: $origen con destino: $destino."
    else
        log_message "Error al sincronizar origen: $origen con destino: $destino. Consulta $LOG_FILE para más detalles."
    fi
done

log_message "Proceso de copia de seguridad con rclone finalizado."