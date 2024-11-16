#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Script Name: backup_rclone_simple.sh
# Description: Realiza copias de seguridad utilizando rclone para múltiples directorios.
# Author: Juan José Hipólito
# Version: 0.3
# Date: 2024-11-08
# License: MIT License
# Usage: Ejecuta el script manualmente.

# Variables
LOG_DIR="/opt/confiraspa/logs"
LOG_FILE="$LOG_DIR/backup_rclone_simple_$(date +'%Y-%m-%d_%H-%M-%S').log"
RCLONE_CONFIG="/home/pi/.config/rclone/rclone.conf"
CONFIG_FILE="/opt/confiraspa/configs/backup_rclone_config.json"

# Crear directorio de logs si no existe
mkdir -p "$LOG_DIR"

# Función para loguear mensajes
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

# Iniciar el proceso
log_message "INFO" "Iniciando el proceso de copia de seguridad con rclone..."

# Verificar la existencia del archivo de configuración
if [ ! -f "$CONFIG_FILE" ]; then
    log_message "ERROR" "Archivo de configuración no encontrado en '$CONFIG_FILE'."
    exit 1
fi

# Validar el archivo JSON
if ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
    log_message "ERROR" "El archivo de configuración '$CONFIG_FILE' no es un JSON válido."
    exit 1
fi

# Leer todas las tareas en un array
mapfile -t tasks < <(jq -c '.directorios[]' "$CONFIG_FILE")

# Verificar que hay tareas
if [ "${#tasks[@]}" -eq 0 ]; then
    log_message "ERROR" "No hay tareas definidas en el archivo de configuración."
    exit 1
fi

# Iterar sobre cada tarea
for task in "${tasks[@]}"; do
    # Extraer 'origen' y 'destino' usando el método original
    origen=$(echo "$task" | jq -r '.origen')
    destino=$(echo "$task" | jq -r '.destino')

    # Validar que 'origen' y 'destino' no estén vacíos
    if [ -z "$origen" ] || [ -z "$destino" ]; then
        log_message "ERROR" "La entrada en el archivo de configuración no tiene 'origen' o 'destino'. Saltando..."
        continue
    fi

    log_message "INFO" "Sincronizando desde '$origen' hacia '$destino'..."

    # Ejecutar rclone sync con reintentos
    max_retries=3
    retry_count=0
    success=false

    while [ $retry_count -lt $max_retries ]; do
        if rclone sync "$origen" "$destino" --config="$RCLONE_CONFIG" --verbose >> "$LOG_FILE" 2>&1; then
            success=true
            break
        else
            log_message "WARN" "Error al sincronizar '$origen' hacia '$destino'. Reintentando ($((retry_count+1))/$max_retries)..."
            retry_count=$((retry_count+1))
            sleep 5  # Espera 5 segundos antes del siguiente intento
        fi
    done

    if [ "$success" = true ]; then
        log_message "INFO" "Sincronización completada para '$origen' hacia '$destino'."
    else
        log_message "ERROR" "Sincronización fallida para '$origen' hacia '$destino' después de $max_retries intentos."
    fi
done

# Fin del proceso
log_message "INFO" "Proceso de copia de seguridad con rclone finalizado."
