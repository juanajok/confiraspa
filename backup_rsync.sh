#!/bin/bash
set -euo pipefail

# Script Name: backup_rsync.sh
# Description: Script para realizar copias de seguridad usando rsync
# Author: Juan José Hipólito
# Version: 1.6.0
# Date: 2024-11-08
# License: GNU
# Usage: Ejecuta el script manualmente o programa su ejecución en crontab
# Dependencies: rsync y jq
# Notes: Asegúrate de que las rutas de origen y destino estén montadas antes de ejecutar este script

# Variables
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="/opt/confiraspa/configs/backup_rsync_config.json"  # Asegúrate de que esta ruta es correcta
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/backup_rsync_$(date +'%Y-%m-%d_%H-%M-%S').log"

# Crear directorio de logs si no existe
mkdir -p "$LOG_DIR"

# Funciones
log_message() {
    local level="$1"
    local message="$2"
    echo "$(date +'%Y-%m-%d %H:%M:%S') - [$level] - $message" | tee -a "$LOG_FILE"
}

# Verificar que rsync está instalado
if ! command -v rsync >/dev/null 2>&1; then
    log_message "ERROR" "'rsync' no está instalado. Por favor, instálalo antes de ejecutar este script."
    exit 1
fi

# Verificar que jq está instalado
if ! command -v jq >/dev/null 2>&1; then
    log_message "ERROR" "'jq' no está instalado. Por favor, instálalo antes de ejecutar este script."
    exit 1
fi

# Comenzar
log_message "INFO" "Iniciando el proceso de copia de seguridad con rsync..."

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

# Agregar mensaje de depuración para la ruta del archivo JSON
#log_message "DEBUG" "Archivo de configuración: '$CONFIG_FILE'"

# Procesar cada entrada en el array 'directorios' en el archivo de configuración JSON
jq -c '.directorios[]' "$CONFIG_FILE" | while read -r entry; do
    # Imprimir la entrada JSON para depuración
    #log_message "DEBUG" "Entrada JSON: '$entry'"

    # Extraer los datos del JSON
    origen=$(jq -r '.origen' <<< "$entry")
    destino=$(jq -r '.destino' <<< "$entry")

    log_message "INFO" "Procesando backup. Origen='$origen', Destino='$destino'"

    # Determinar si 'origen' es un archivo o directorio
    if [ -d "$origen" ]; then
        tipo="directorio"
    elif [ -f "$origen" ]; then
        tipo="archivo"
    else
        log_message "ERROR" "El origen '$origen' no existe. Saltando..."
        continue
    fi

    # Crear el directorio de destino si no existe
    if [ ! -d "$destino" ]; then
        log_message "INFO" "El directorio de destino '$destino' no existe. Creando..."
        mkdir -p "$destino"
        if [ $? -ne 0 ]; then
            log_message "ERROR" "No se pudo crear el directorio de destino '$destino'. Saltando..."
            continue
        fi
    fi

    # Ejecutar rsync dependiendo del tipo
    log_message "INFO" "Sincronizando '$origen' con '$destino' como $tipo..."
    rsync_options="-avh --delete --stats"

    if [ "$tipo" == "directorio" ]; then
        rsync $rsync_options "$origen"/ "$destino"/ >> "$LOG_FILE" 2>&1
    elif [ "$tipo" == "archivo" ]; then
        rsync $rsync_options "$origen" "$destino"/ >> "$LOG_FILE" 2>&1
    fi

    # Verificar si rsync tuvo éxito
    if [ $? -eq 0 ]; then
        log_message "INFO" "Sincronización completada para '$origen' con '$destino'."
    else
        log_message "ERROR" "Error al sincronizar '$origen' con '$destino'."
    fi

done

log_message "INFO" "Proceso de copia de seguridad con rsync finalizado."
