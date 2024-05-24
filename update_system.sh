#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Imprime un mensaje indicando que se está actualizando la Raspberry Pi
log "1) Actualizando la Raspberry Pi..."

# Actualiza los paquetes y limpia el sistema
apt update && apt upgrade -y && apt dist-upgrade -y && apt autoremove -y && apt clean

# Instala jq si no está instalado
if ! dpkg -s jq >/dev/null 2>&1; then
    apt install -y jq
fi

# Instala moreutils si no está instalado
if ! dpkg -s moreutils >/dev/null 2>&1; then
    apt install -y moreutils
fi

# Comando de actualización semanal
actualizacion_cmd="0 0 * * 1 apt update && apt upgrade -y && apt dist-upgrade -y && apt autoremove -y && apt clean"
# Añade el comando de actualización al crontab del usuario actual si no está ya presente
(crontab -l 2>/dev/null | grep -qF -- "$actualizacion_cmd") || (crontab -l 2>/dev/null; echo "$actualizacion_cmd") | crontab -
