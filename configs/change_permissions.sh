#!/bin/bash
set -euo pipefail

# Script Name: change_permissions.sh
# Description: Cambia la propiedad y los permisos de los directorios especificados en un archivo JSON.
# Author: Juan José Hipólito
# Version: 1.1.0
# Date: 17/04/2023
# License: GNU
# Usage: Ejecuta el script manualmente
# Dependencies: jq

# Variables
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/configs/change_permissions_config.json"

# Funciones
log_message() {
    local level="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [$level] - $message"
}

# Verificar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    log_message "ERROR" "Este script debe ejecutarse con privilegios de superusuario (sudo)."
    exit 1
fi

# Verificar que jq está instalado
if ! command -v jq >/dev/null 2>&1; then
    log_message "ERROR" "'jq' no está instalado. Por favor, instálalo antes de ejecutar este script."
    exit 1
fi

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

# Leer la información del archivo JSON
usuario=$(jq -r '.usuario' "$CONFIG_FILE")
directorios=($(jq -r '.directorios[]' "$CONFIG_FILE"))
permisos=$(jq -r '.permisos' "$CONFIG_FILE")

# Validar que los valores no están vacíos
if [ -z "$usuario" ]; then
    log_message "ERROR" "El usuario no está especificado en el archivo de configuración."
    exit 1
fi

if [ ${#directorios[@]} -eq 0 ]; then
    log_message "ERROR" "No se han especificado directorios en el archivo de configuración."
    exit 1
fi

if [ -z "$permisos" ]; then
    permisos="755"  # Valor por defecto
    log_message "INFO" "No se especificaron permisos en el archivo de configuración. Se utilizará el valor por defecto: $permisos"
fi

log_message "INFO" "Usuario: $usuario"
log_message "INFO" "Permisos: $permisos"
log_message "INFO" "Directorios:"

for dir in "${directorios[@]}"; do
    log_message "INFO" "Procesando directorio: '$dir'"

    # Verificar que el directorio existe
    if [ ! -e "$dir" ]; then
        log_message "ERROR" "El directorio '$dir' no existe. Saltando..."
        continue
    fi

    # Cambiar la propiedad del directorio
    if chown -R "$usuario":"$usuario" "$dir"; then
        log_message "INFO" "Propiedad cambiada a '$usuario' en '$dir'"
    else
        log_message "ERROR" "Error al cambiar la propiedad en '$dir'"
    fi

    # Cambiar permisos del directorio
    if chmod -R "$permisos" "$dir"; then
        log_message "INFO" "Permisos cambiados a '$permisos' en '$dir'"
    else
        log_message "ERROR" "Error al cambiar los permisos en '$dir'"
    fi
done

log_message "INFO" "Proceso completado."

