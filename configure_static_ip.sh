#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Imprime un mensaje indicando que se está configurando la IP estática
log "Configurando IP estática usando nmcli..."

# Verifica si nmcli está instalado, si no, lo instala
if ! command -v nmcli > /dev/null; then
    apt-get install -y network-manager
fi

# Verifica si el archivo network_config.json existe
if [ ! -f network_config.json ]; then
    log "Error: El archivo network_config.json no se encuentra."
    exit 1
fi

# Lee la configuración de red del archivo network_config.json
config=$(cat network_config.json)

# Extrae las variables de la configuración
CONEXION=$(echo "$config" | jq -r '.conexion')
IP_ESTATICA=$(echo "$config" | jq -r '.ip_estatica')
GATEWAY=$(echo "$config" | jq -r '.gateway')
DNS=$(echo "$config" | jq -r '.dns')
MASCARA=$(echo "$config" | jq -r '.mascara')

# Verifica si la conexión existe
if ! nmcli con show | grep -q "$CONEXION"; then
    log "Error: La conexión $CONEXION no existe."
    exit 1
fi

# Encuentra el nombre del dispositivo asociado con esta conexión
NOMBRE_DISPOSITIVO=$(nmcli -t -f DEVICE,CONNECTION device | grep "$CONEXION" | cut -d: -f1)

# Verifica si la IP estática ya está configurada
if nmcli con show "$CONEXION" | grep -q "$IP_ESTATICA"; then
    log "La IP estática ya está configurada."
else
    # Configura la IP estática, gateway y DNS
    nmcli con mod "$CONEXION" ipv4.addresses "$IP_ESTATICA/$MASCARA"
    nmcli con mod "$CONEXION" ipv4.gateway "$GATEWAY"
    nmcli con mod "$CONEXION" ipv4.dns "$DNS"
    nmcli con mod "$CONEXION" ipv4.method manual

    # Reinicia la conexión para aplicar los cambios
    nmcli con down "$CONEXION" && nmcli con up "$CONEXION"
    log "Configuración de IP estática aplicada a la conexión $CONEXION"
fi
