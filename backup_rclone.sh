#!/bin/bash
set -euo pipefail

# Script Name: backup_rclone.sh
# Description: Script para realizar copias de seguridad en la nube usando rclone
# Author: Juan José Hipólito
# Version: 1.3.0
# Date: 2023-08-03
# License: GNU
# Usage: Ejecuta el script manualmente o programa su ejecución en crontab
# Dependencies: rclone y jq
# Notes: Asegúrate de que las rutas de origen y destino estén montadas antes de ejecutar este script

# Variables
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/configs/backup_rclone_config.json"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/backup_rclone_$(date +'%Y-%m-%d_%H-%M-%S').log"
RCLONE_CONFIG="/home/pi/.config/rclone/rclone.conf"  # Ruta al archivo de configuración de rclone

# Crear directorio de logs si no existe
mkdir -p "$LOG_DIR"

# Funciones
log_message() {
    local level="$1"
    local message="$2"
    echo "$(date +'%Y-%m-%d %H:%M:%S') - [$level] - $message" | tee -a "$LOG_FILE"
}

# Verificar que rclone está instalado
if ! command -v rclone >/dev/null 2>&1; then
    log_message "ERROR" "'rclone' no está instalado. Por favor, instálalo antes de ejecutar este script."
    exit 1
fi

# Verificar que jq está instalado
if ! command -v jq >/dev/null 2>&1; then
    log_message "ERROR" "'jq' no está instalado. Por favor, instálalo antes de ejecutar este script."
    exit 1
fi

# Verificar la existencia del archivo de configuración de rclone
if [ ! -f "$RCLONE_CONFIG" ]; then
    log_message "ERROR" "El archivo de configuración de rclone '$RCLONE_CONFIG' no existe."
    exit 1
fi

# Comenzar
log_message "INFO" "Iniciando el proceso de copia de seguridad con rclone..."

# Verificar la existencia del archivo de configuración
if [ ! -f "$CONFIG_FILE" ]; then
    log_message "ERROR" "Archivo de configuración '$CONFIG_FILE' no encontrado."
    exit 1
fi

# Validar el archivo JSON
if ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
    log_message "ERROR" "El archivo de configuración '$CONFIG_FILE' no es un JSON válido."
    exit 1
fi

# Leer el archivo JSON con las rutas de las carpetas y ejecutar rclone para cada par de directorios origen y destino
while read -r dir_info; do
    origen=$(echo "$dir_info" | jq -r '.origen')
    destino=$(echo "$dir_info" | jq -r '.destino')

    # Verificar que el directorio de origen existe
    if [ ! -d "$origen" ]; then
        log_message "ERROR" "El directorio de origen '$origen' no existe. Saltando..."
        continue
    fi

    log_message "INFO" "Sincronizando origen: '$origen' con destino: '$destino'..."

    # Ejecutar rclone
    rclone_options="--config=\"$RCLONE_CONFIG\" --verbose"
    if rclone sync "$origen" "$destino" $rclone_options >> "$LOG_FILE" 2>&1; then
        log_message "INFO" "Sincronización completada para origen: '$origen' con destino: '$destino'."
    else
        log_message "ERROR" "Error al sincronizar origen: '$origen' con destino: '$destino'."
    fi

done < <(jq -c '.directorios[]' "$CONFIG_FILE")

log_message "INFO" "Proceso de copia de seguridad con rclone finalizado."
