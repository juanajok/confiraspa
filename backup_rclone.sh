#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Script Name: backup_rclone_simple.sh
# Description: Realiza copias de seguridad utilizando rclone para múltiples directorios.
# Author: Juan José Hipólito
# Version: 0.2
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

# Iniciar el proceso
log_message "INFO" "Iniciando el proceso de copia de seguridad con rclone..."

# Leer todas las tareas en un array
mapfile -t tasks < <(jq -c '.directorios[]' "$CONFIG_FILE")

# Verificar que hay tareas
if [ "${#tasks[@]}" -eq 0 ]; then
    log_message "ERROR" "No hay tareas definidas en el archivo de configuración."
    exit 1
fi

# Iterar sobre cada tarea
for task in "${tasks[@]}"; do
    origen=$(echo "$task" | jq -r '.origen')
    destino=$(echo "$task" | jq -r '.destino')

    # Validar que 'origen' y 'destino' no estén vacíos
    if [ -z "$origen" ] || [ -z "$destino" ]; then
        log_message "ERROR" "La entrada en el archivo de configuración no tiene 'origen' o 'destino'. Saltando..."
        continue
    fi

    log_message "INFO" "Sincronizando desde '$origen' hacia '$destino'..."
    log_message "DEBUG" "Ejecutando: rclone sync '$origen' '$destino' --config='$RCLONE_CONFIG' --verbose"

    # Ejecutar rclone sync y capturar el estado de salida
    if rclone sync "$origen" "$destino" --config="$RCLONE_CONFIG" --verbose >> "$LOG_FILE" 2>&1; then
        log_message "INFO" "Sincronización completada para '$origen' hacia '$destino'."
    else
        log_message "ERROR" "Error al sincronizar '$origen' hacia '$destino'."
    fi
done

# Fin del proceso
log_message "INFO" "Proceso de copia de seguridad con rclone finalizado."

