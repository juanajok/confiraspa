#!/bin/bash
# Script Name: change_permissions.sh
# Description: Cambia la propiedad y los permisos de los directorios especificados en un archivo JSON.
# Author: Juan José Hipólito
# Version: 1.2.0
# Date: 2024-11-08
# License: GNU
# Usage: Ejecuta el script manualmente
# Dependencies: jq

# --- Cargar Funciones Comunes ---
source /opt/confiraspa/lib/utils.sh

check_root
setup_error_handling
install_dependencies "jq"  # dependencias

# Variables
CONFIG_FILE="$CONFIG_DIR/change_permissions_config.json"

# Verificar la existencia del archivo de configuración
if [ ! -f "$CONFIG_FILE" ]; then
    log "ERROR" "Archivo de configuración '$CONFIG_FILE' no encontrado."
    exit 1
fi

# Validar el archivo JSON
if ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
    log "ERROR" "El archivo de configuración '$CONFIG_FILE' no es un JSON válido."
    exit 1
fi

# Leer la información del archivo JSON
usuario=$(jq -r '.usuario' "$CONFIG_FILE")
permisos=$(jq -r '.permisos' "$CONFIG_FILE")

# Leer los directorios en un array, preservando espacios
readarray -t directorios < <(jq -r '.directorios[]' "$CONFIG_FILE")

# Validar que los valores no están vacíos
if [ -z "$usuario" ]; then
    log "ERROR" "El usuario no está especificado en el archivo de configuración."
    exit 1
fi

if [ ${#directorios[@]} -eq 0 ]; then
    log "ERROR" "No se han especificado directorios en el archivo de configuración."
    exit 1
fi

if [ -z "$permisos" ]; then
    permisos="755" # Valor por defecto
    log "INFO" "No se especificaron permisos en el archivo de configuración. Se utilizará el valor por defecto: $permisos"
fi

log "INFO" "Usuario: $usuario"
log "INFO" "Permisos: $permisos"
log "INFO" "Directorios:"

for dir in "${directorios[@]}"; do
    log "INFO" "Procesando directorio: '$dir'"

    # Verificar que el directorio existe
    if [ ! -e "$dir" ]; then
        log "ERROR" "El directorio '$dir' no existe. Saltando..."
        continue
    fi

    # Cambiar la propiedad del directorio
    if chown -R "$usuario":"$usuario" "$dir"; then
        log "INFO" "Propiedad cambiada a '$usuario' en '$dir'"
    else
        log "ERROR" "Error al cambiar la propiedad en '$dir'"
    fi

    # Cambiar permisos del directorio
    if chmod -R "$permisos" "$dir"; then
        log "INFO" "Permisos cambiados a '$permisos' en '$dir'"
    else
        log "ERROR" "Error al cambiar los permisos en '$dir'"
    fi
done

log "INFO" "Proceso completado."

