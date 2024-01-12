#!/bin/bash

# Configuraciones deseadas
INTERFAZ="eth0" # Cambiar a wlan0 para Wi-Fi
IP_ESTATICA="192.168.1.76"
GATEWAY="192.168.1.1"
DNS="8.8.8.8,8.8.4.4" # Separados por comas sin espacios
MASCARA="24"

# Verifica si el usuario es root
if [ "$(id -u)" != "0" ]; then
   echo "Este script debe ser ejecutado como root" >&2
   exit 1
fi

# Verifica la existencia de la interfaz
if ! nmcli device status | grep -q "$INTERFAZ"; then
    echo "La interfaz $INTERFAZ no existe o no está activa." >&2
    exit 1
fi

# Función para validar la dirección IP y la máscara de red
validar_ip_mascara() {
    local ip_mascara=$1
    if ! echo $ip_mascara | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]+$'; then
        echo "Formato de dirección IP/máscara no válido: $ip_mascara" >&2
        return 1
    fi
    return 0
}

# Función para validar la dirección de la puerta de enlace
validar_gateway() {
    local gw=$1
    if ! echo $gw | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
        echo "Formato de dirección de la puerta de enlace no válido: $gw" >&2
        return 1
    fi
    return 0
}

# Función para validar los servidores DNS
validar_dns() {
    local dns=$1
    if ! echo $dns | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}(,[0-9]{1,3}\.){3}[0-9]{1,3}$'; then
        echo "Formato de servidores DNS no válido: $dns" >&2
        return 1
    fi
    return 0
}

# Valida las entradas
if ! validar_ip_mascara "$IP_ESTATICA/$MASCARA" || ! validar_gateway "$GATEWAY" || ! validar_dns "$DNS"; then
    exit 1
fi

# Obtiene la configuración actual
ACTUAL_IP=$(nmcli -g IP4.ADDRESS dev show $INTERFAZ)
ACTUAL_GATEWAY=$(nmcli -g IP4.GATEWAY dev show $INTERFAZ)
ACTUAL_DNS=$(nmcli -g IP4.DNS dev show $INTERFAZ | paste -sd "," -)

# Compara la configuración actual con la deseada
if [ "$ACTUAL_IP" = "$IP_ESTATICA/$MASCARA" ] && [ "$ACTUAL_GATEWAY" = "$GATEWAY" ] && [ "$ACTUAL_DNS" = "$DNS" ]; then
    echo "La configuración de red ya está establecida. No se requieren cambios."
    exit 0
fi

# Aplica la configuración
if nmcli con mod "$INTERFAZ" ipv4.addresses "$IP_ESTATICA/$MASCARA" &&
   nmcli con mod "$INTERFAZ" ipv4.gateway "$GATEWAY" &&
   nmcli con mod "$INTERFAZ" ipv4.dns "$DNS" &&
   nmcli con mod "$INTERFAZ" ipv4.method manual; then

    # Reinicia la interfaz de red para aplicar los cambios
    nmcli con down "$INTERFAZ" && nmcli con up "$INTERFAZ"
    echo "Configuración de IP estática aplicada a $INTERFAZ"
else
    echo "Error al aplicar la configuración a $INTERFAZ" >&2
    exit 1
fi
