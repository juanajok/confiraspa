#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Imprime un mensaje indicando que se está instalando Mono
log "9) Instalando Mono..."

# Verifica si Mono ya está instalado
if dpkg -s mono-devel >/dev/null 2>&1; then
    log "Mono ya está instalado."
    exit 0
fi

# Instala dependencias y agrega el repositorio de Mono
apt install -y apt-transport-https dirmngr gnupg ca-certificates

# Agrega la clave del repositorio de Mono
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF

# Agrega el repositorio de Mono a la lista de fuentes
echo "deb https://download.mono-project.com/repo/debian stable-buster main" | tee /etc/apt/sources.list.d/mono-official-stable.list

# Actualiza la lista de paquetes y instala Mono
apt update
apt install -y mono-devel

log "Mono instalado con éxito."
