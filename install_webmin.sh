#!/bin/bash
set -euo pipefail

# Script Name: install_webmin.sh
# Description: Instala y configura Webmin en Raspberry OS de forma segura.
# Author: [Tu Nombre]
# Version: 2.1.0
# Date: [Fecha Actual]
# License: GNU

# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

log "INFO" "11) Instalando Webmin..."

# Verifica si Webmin ya está instalado
if dpkg-query -W -f='${Status}' webmin 2>/dev/null | grep -q "install ok installed"; then
    log "INFO" "Webmin ya está instalado en el sistema."
    exit 0
fi

# Añade la clave GPG de Webmin de forma segura
log "INFO" "Añadiendo la clave GPG de Webmin..."
if ! wget -qO - http://www.webmin.com/jcameron-key.asc | gpg --dearmor | tee /usr/share/keyrings/webmin.gpg >/dev/null; then
    log "ERROR" "No se pudo añadir la clave GPG de Webmin."
    exit 1
fi

# Añade el repositorio de Webmin al archivo sources.list.d
log "INFO" "Añadiendo el repositorio de Webmin..."
echo "deb [signed-by=/usr/share/keyrings/webmin.gpg] http://download.webmin.com/download/repository sarge contrib" | tee /etc/apt/sources.list.d/webmin.list >/dev/null

# Actualiza la lista de paquetes
log "INFO" "Actualizando la lista de paquetes..."
apt-get update -qq

# Instala Webmin
log "INFO" "Instalando Webmin..."
if ! apt-get install -y webmin; then
    log "ERROR" "No se pudo instalar Webmin."
    exit 1
fi

# Verifica si Webmin se instaló correctamente
if dpkg-query -W -f='${Status}' webmin 2>/dev/null | grep -q "install ok installed"; then
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    log "INFO" "Webmin instalado correctamente. Acceda a la interfaz de Webmin en https://$IP_ADDRESS:10000"
else
    log "ERROR" "No se pudo instalar Webmin correctamente."
    exit 1
fi
