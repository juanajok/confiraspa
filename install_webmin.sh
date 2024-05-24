#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Imprime un mensaje indicando que se está instalando Webmin
log "11) Instalando Webmin..."

# Verifica si Webmin ya está instalado
if dpkg-query -W -f='${Status}' webmin | grep -q "installed"; then
    log "Webmin ya está instalado en el sistema."
    exit 0
fi

# Descarga e instala el script de configuración de repositorios de Webmin
curl -o setup-repos.sh https://raw.githubusercontent.com/webmin/webmin/master/setup-repos.sh
sh setup-repos.sh

# Actualiza la lista de paquetes e instala Webmin
apt-get update
apt-get install -y webmin

# Verifica si Webmin se instaló correctamente
if dpkg-query -W -f='${Status}' webmin | grep -q "installed"; then
    log "Webmin instalado correctamente. Acceda a la interfaz de Webmin en https://[tu-ip]:10000"
    exit 0
else
    log "Error: No se pudo instalar Webmin correctamente."
    exit 1
fi
