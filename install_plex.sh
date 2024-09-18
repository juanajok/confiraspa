#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Imprime un mensaje indicando que se está instalando Plex Media Server
log "Instalando Plex Media Server..."

# Actualiza la lista de paquetes y actualiza los paquetes existentes
apt-get update -y
apt-get upgrade -y

# Verifica si Plex Media Server ya está instalado
if ! dpkg -s plexmediaserver >/dev/null 2>&1; then
    wget -O plex.deb https://downloads.plex.tv/plex-media-server-new/1.32.0.6918-6f393eda1/debian/plexmediaserver_1.32.0.6918-6f393eda1_armhf.deb
    dpkg -i plex.deb
    rm plex.deb
else
    log "Plex Media Server ya está instalado."
fi

# Verifica si el servicio Plex Media Server está habilitado y activo
if systemctl is-active --quiet plexmediaserver.service; then
    log "Plex Media Server ya está habilitado e iniciado."
else
    systemctl enable plexmediaserver.service
    systemctl start plexmediaserver.service
    log "Plex Media Server habilitado e iniciado."
fi

log "Plex Media Server instalado. Visita http://$(hostname -I | awk '{print $1}'):32400/web para configurarlo."
