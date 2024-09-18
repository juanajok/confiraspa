#!/bin/bash
set -euo pipefail

# Script Name: setup_credentials.sh
# Description: Configura variables de usuario y contraseña para su uso en otros scripts, leyendo desde un archivo JSON.
# Author: Juan José Hipólito
# Version: 2.1.0
# Date: 2023-03-30
# License: GNU
# Usage: Ejecutar este script como superusuario (sudo).
# Notes:
# - El archivo 'credenciales.json' debe estar ubicado en '/configs'.
# - Asegúrate de que el usuario tiene permisos de lectura en '/configs/credenciales.json'.

# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

# Verificar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    log "ERROR" "Por favor, ejecuta el script como superusuario (sudo)."
    exit 1
fi

# Definir variables de usuario y grupo
usuario="${SUDO_USER:-$(whoami)}"
app_guid=$(id -gn "$usuario")

# Verificar si el archivo credenciales.json existe en /configs
CONFIG_DIR="/configs"
CREDENTIALS_FILE="$CONFIG_DIR/credenciales.json"

if [ ! -f "$CREDENTIALS_FILE" ]; then
    log "ERROR" "El archivo 'credenciales.json' no se encuentra en '$CONFIG_DIR'."
    exit 1
fi

# Leer las credenciales del archivo credenciales.json
if ! contrasena=$(jq -r '.password' "$CREDENTIALS_FILE"); then
    log "ERROR" "No se pudo leer la contraseña del archivo 'credenciales.json'."
    exit 1
fi

# Verificar que la contraseña no esté vacía
if [ -z "$contrasena" ]; then
    log "ERROR" "La contraseña en 'credenciales.json' está vacía."
    exit 1
fi

log "INFO" "Se usará el usuario '$usuario' para el resto de instalaciones."
script_path="$(dirname "$(realpath "$0")")"

# Exportar variables para que estén disponibles en otros scripts
export usuario
export app_guid
export contrasena

log "INFO" "Variables de usuario y contraseña configuradas correctamente."

