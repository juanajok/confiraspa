#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Verifica si el script se está ejecutando como superusuario
if [ "$EUID" -ne 0 ]; then
    log "Error: Por favor, ejecuta el script como superusuario (sudo)."
    exit 1
fi

# Define variables de usuario y grupo
usuario="$SUDO_USER"
app_guid=$(id -gn "$usuario")

# Verifica si el archivo credenciales.json existe
if [ ! -f credenciales.json ]; then
    log "Error: El archivo credenciales.json no se encuentra."
    exit 1
fi

# Lee las credenciales del archivo credenciales.json
credenciales=$(cat credenciales.json)
contrasena=$(echo "$credenciales" | jq -r '.password')
log "Info: Se usará el usuario $usuario para el resto de instalaciones"
script_path="$(dirname "$(realpath "$0")")"
