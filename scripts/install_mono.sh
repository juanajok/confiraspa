#!/bin/bash
set -euo pipefail

# Script Name: install_mono.sh
# Description: Script para instalar Mono en sistemas Debian/Ubuntu
# Author: [Tu Nombre]
# Version: 1.1.0
# Date: [Fecha Actual]
# License: GNU
# Usage: Ejecuta el script con privilegios de superusuario
# Notes: Asegúrate de tener conexión a Internet y privilegios de superusuario

# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

# Verificar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    log "ERROR" "Este script debe ejecutarse con privilegios de superusuario (sudo)."
    exit 1
fi

log "INFO" "9) Instalando Mono..."

# Verificar si Mono ya está instalado
if dpkg -s mono-devel >/dev/null 2>&1; then
    log "INFO" "Mono ya está instalado."
    exit 0
fi

# Instalar dependencias necesarias
log "INFO" "Instalando dependencias..."
apt-get update
apt-get install -y apt-transport-https dirmngr gnupg ca-certificates

# Agregar la clave GPG del repositorio de Mono
log "INFO" "Agregando clave GPG del repositorio de Mono..."
wget -qO- https://download.mono-project.com/repo/xamarin.gpg | gpg --dearmor > /usr/share/keyrings/mono-archive-keyring.gpg

# Agregar el repositorio de Mono a la lista de fuentes
log "INFO" "Agregando el repositorio de Mono..."
echo "deb [signed-by=/usr/share/keyrings/mono-archive-keyring.gpg] https://download.mono-project.com/repo/debian stable-buster main" | tee /etc/apt/sources.list.d/mono-official-stable.list

# Actualizar la lista de paquetes e instalar Mono
log "INFO" "Actualizando la lista de paquetes..."
apt-get update

log "INFO" "Instalando Mono..."
apt-get install -y mono-devel

log "INFO" "Mono instalado con éxito."

