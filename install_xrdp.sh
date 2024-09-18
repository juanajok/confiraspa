#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Imprime un mensaje indicando que se está instalando XRDP
log "7) Instalando Escritorio Remoto (XRDP)..."

# Verifica si XRDP ya está instalado
if dpkg -s xrdp >/dev/null 2>&1; then
    log "XRDP ya está instalado en el sistema."
    exit 0
fi

# Instala XRDP
apt-get install -y xrdp
log "XRDP instalado correctamente."
