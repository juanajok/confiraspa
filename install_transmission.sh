#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Imprime un mensaje indicando que se está instalando Transmission
log "8) Instalando Transmission..."

# Verifica si Transmission ya está instalado
if ! dpkg -s transmission-daemon >/dev/null 2>&1; then
    apt-get install -y transmission-daemon || { log "Error al instalar transmission-daemon."; exit 1; }
else
    log "El paquete transmission-daemon ya está instalado."
fi

# Detiene el servicio de Transmission antes de modificar la configuración
systemctl stop transmission-daemon

# Verifica si el archivo de configuración existe
if [ ! -f transmission.json ]; then
    log "Error: El archivo transmission.json no se encuentra."
    exit 1
fi

# Lee la configuración del archivo JSON
config=$(cat transmission.json)
download_dir=$(echo "$config" | jq -r '.["download-dir"]')
incomplete_dir=$(echo "$config" | jq -r '.["incomplete-dir"]')
incomplete_dir_enabled=$(echo "$config" | jq -r '.["incomplete-dir-enabled"]')
rpc_auth_required=$(echo "$config" | jq -r '.["rpc-authentication-required"]')
rpc_enabled=$(echo "$config" | jq -r '.["rpc-enabled"]')
rpc_password=$(echo "$config" | jq -r '.["rpc-password"]')
rpc_whitelist_enabled=$(echo "$config" | jq -r '.["rpc-whitelist-enabled"]')

# Define el archivo de configuración de Transmission
CONFIG_FILE="/etc/transmission-daemon/settings.json"
if [ -f "$CONFIG_FILE" ]; then
    # Crea una copia de seguridad del archivo de configuración
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
    log "Copia de seguridad del archivo de configuración realizada."

    # Actualiza el archivo de configuración con los nuevos valores
    jq --arg download_dir "$download_dir" \
       --arg incomplete_dir "$incomplete_dir" \
       --argjson incomplete_dir_enabled "$incomplete_dir_enabled" \
       --argjson rpc_auth_required "$rpc_auth_required" \
       --argjson rpc_enabled "$rpc_enabled" \
       --arg rpc_password "$rpc_password" \
       --argjson rpc_whitelist_enabled "$rpc_whitelist_enabled" \
       '.["download-dir"]=$download_dir | .["incomplete-dir"]=$incomplete_dir | .["incomplete-dir-enabled"]=$incomplete_dir_enabled | .["rpc-authentication-required"]=$rpc_auth_required | .["rpc-enabled"]=$rpc_enabled | .["rpc-password"]=$rpc_password | .["rpc-whitelist-enabled"]=$rpc_whitelist_enabled' "$CONFIG_FILE" | sponge "$CONFIG_FILE"
else
    log "No se encontró el archivo de configuración de Transmission."
    exit 1
fi

# Inicia el servicio de Transmission
systemctl start transmission-daemon || { log "Error al reiniciar el servicio de Transmission."; exit 1; }
log "Servicio de Transmission reiniciado."
