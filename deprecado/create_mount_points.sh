#!/bin/bash
set -e

# Descripción: Este script crea puntos de montaje según una configuración en JSON.
# Autor: [Tu Nombre]
# Fecha: [Fecha]
# Versión: 1.0.0

# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

# Verificar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    log "ERROR" "Este script debe ser ejecutado con privilegios de superusuario (sudo)."
    exit 1
fi

# Ruta del script y del archivo JSON
script_dir="$(dirname "$(realpath "$0")")"
json_file="$script_dir/configs/puntos_de_montaje.json"

# Verificar si el archivo JSON existe
if [ ! -f "$json_file" ]; then
    log "ERROR" "No se encuentra el archivo de configuración $json_file."
    exit 1
fi

log "INFO" "Iniciando la creación de puntos de montaje..."

# Leer los puntos de montaje del archivo JSON
mount_points=$(jq -r '.puntos_de_montaje[]' "$json_file")

# Crear cada punto de montaje y aplicar permisos
for dir in $mount_points; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        chmod 777 "$dir"
        log "INFO" "Punto de montaje creado: $dir"
    else
        log "INFO" "El punto de montaje $dir ya existe."
    fi
done

log "INFO" "Finalizando la creación de puntos de montaje."

