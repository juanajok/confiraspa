#!/bin/bash

# Configuraciones deseadas
CONEXION="Wired connection 1" # Cambiar a wlan0 para Wi-Fi
IP_ESTATICA="192.168.1.76"
GATEWAY="192.168.1.1"
DNS="8.8.8.8,8.8.4.4" # Separados por comas sin espacios
MASCARA="24"

# Verifica si el usuario es root
if [ "$(id -u)" != "0" ]; then
   echo "Este script debe ser ejecutado como root" >&2
   exit 1
fi

# Verifica la existencia de la CONEXION
if ! nmcli device status | grep -q "$CONEXION"; then
    echo "La CONEXION $CONEXION no existe o no está activa." >&2
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
    # Esta expresión regular verifica uno o más servidores DNS válidos, separados por comas.
    if ! echo $dns | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}(,([0-9]{1,3}\.){3}[0-9]{1,3})*$'; then
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
ACTUAL_IP=$(nmcli -g IP4.ADDRESS dev show $CONEXION)
ACTUAL_GATEWAY=$(nmcli -g IP4.GATEWAY dev show $CONEXION)
ACTUAL_DNS=$(nmcli -g IP4.DNS dev show $CONEXION | paste -sd "," -)

# Compara la configuración actual con la deseada
if [ "$ACTUAL_IP" = "$IP_ESTATICA/$MASCARA" ] && [ "$ACTUAL_GATEWAY" = "$GATEWAY" ] && [ "$ACTUAL_DNS" = "$DNS" ]; then
    echo "La configuración de red ya está establecida. No se requieren cambios."
    exit 0
fi

# Aplica la configuración
if nmcli con mod "$CONEXION" ipv4.addresses "$IP_ESTATICA/$MASCARA" &&
   nmcli con mod "$CONEXION" ipv4.gateway "$GATEWAY" &&
   nmcli con mod "$CONEXION" ipv4.dns "$DNS" &&
   nmcli con mod "$CONEXION" ipv4.method manual; then

    # Reinicia la CONEXION de red para aplicar los cambios
    nmcli con down "$CONEXION" && nmcli con up "$CONEXION"
    echo "Configuración de IP estática aplicada a $CONEXION"
else
    echo "Error al aplicar la configuración a $CONEXION" >&2
    exit 1
fi
