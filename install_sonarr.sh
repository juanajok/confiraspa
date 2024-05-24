#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Imprime un mensaje indicando que se está instalando Sonarr
log "10) Instalando Sonarr..."

# Verifica si Sonarr ya está instalado
if dpkg -s sonarr > /dev/null 2>&1; then
    log "Sonarr ya está instalado, saltando..."
    exit 0
fi

# Agrega la clave del repositorio de Sonarr
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 2009837CBFFD68F45BC180471F4F90DE2A9B4BF8

# Agrega el repositorio de Sonarr a la lista de fuentes
echo "deb https://apt.sonarr.tv/debian buster main" | tee /etc/apt/sources.list.d/sonarr.list

# Actualiza la lista de paquetes y instala Sonarr
apt update
apt install -y sonarr

log "Sonarr instalado correctamente."
