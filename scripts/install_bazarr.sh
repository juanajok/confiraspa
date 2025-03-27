#!/bin/bash
set -e

# Script Name: install_bazarr.sh
# Description: Este script instala y configura Bazarr en una Raspberry Pi con Raspbian OS.
# Author: [Tu Nombre]
# Version: 1.1.1
# Date: [Fecha]
# License: MIT License

# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

# Verificar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    log "ERROR" "Este script debe ser ejecutado con privilegios de superusuario (sudo)."
    exit 1
fi

# Usuario que ejecutará Bazarr
usuario="${SUDO_USER:-$(whoami)}"

log "INFO" "Instalando dependencias de Bazarr..."

# Actualizar lista de paquetes
apt-get update

# Instalar dependencias necesarias para Bazarr
apt-get install -y \
    libxml2-dev \
    libxslt1-dev \
    python3-dev \
    python3-libxml2 \
    python3-lxml \
    unrar-free \
    ffmpeg \
    libatlas-base-dev \
    python3-venv \
    unzip

# Crear directorio para Bazarr
install_dir="/opt/bazarr"

if [ ! -d "$install_dir" ]; then
    log "INFO" "Creando directorio para Bazarr..."
    mkdir -p "$install_dir"
    chown -R "$usuario":"$usuario" "$install_dir"
    chmod -R 755 "$install_dir"
fi

# Descargar y descomprimir Bazarr
log "INFO" "Descargando y descomprimiendo Bazarr..."

bazarr_zip_url="https://github.com/morpheus65535/bazarr/releases/latest/download/bazarr.zip"
bazarr_zip_file="$install_dir/bazarr.zip"

# Descargar bazarr.zip solo si no existe o si hay una versión más reciente
wget -O "$bazarr_zip_file" "$bazarr_zip_url"

# Descomprimir bazarr.zip, sobrescribiendo archivos sin preguntar
unzip -oq -d "$install_dir" "$bazarr_zip_file"

# Eliminar el archivo bazarr.zip después de descomprimir
rm "$bazarr_zip_file"

# Crear entorno virtual si no existe
if [ ! -d "$install_dir/venv" ]; then
    log "INFO" "Creando entorno virtual para Bazarr..."
    python3 -m venv "$install_dir/venv"
fi

# Instalar dependencias de Bazarr en el entorno virtual
log "INFO" "Instalando dependencias de Bazarr en el entorno virtual..."
"$install_dir/venv/bin/pip" install -U pip
"$install_dir/venv/bin/pip" install -U wheel setuptools
"$install_dir/venv/bin/pip" install -U -r "$install_dir/requirements.txt"

# Ajustes para arquitecturas específicas
arch=$(uname -m)
if [[ "$arch" == "armv6l" ]] || [[ "$arch" == "armv7l" ]] || [[ "$arch" == "aarch64" ]]; then
    log "INFO" "Arquitectura $arch detectada. Realizando ajustes..."
    "$install_dir/venv/bin/pip" uninstall -y numpy || true
    apt-get install -y python3-numpy
fi

# Establecer permisos y propietario adecuados
log "INFO" "Estableciendo permisos para Bazarr..."
chown -R "$usuario":"$usuario" "$install_dir"
chmod -R 755 "$install_dir"

# Crear archivo de servicio systemd para Bazarr
log "INFO" "Creando archivo de servicio systemd para Bazarr..."
cat > /etc/systemd/system/bazarr.service << EOF
[Unit]
Description=Bazarr Daemon
After=network.target

[Service]
WorkingDirectory=$install_dir
User=$usuario
Group=$usuario
UMask=0002
Type=simple
ExecStart=$install_dir/venv/bin/python $install_dir/bazarr.py
Restart=on-failure
RestartSec=5
TimeoutStopSec=20
SyslogIdentifier=bazarr

[Install]
WantedBy=multi-user.target
EOF

# Recargar systemd y habilitar el servicio
log "INFO" "Habilitando y arrancando el servicio Bazarr..."
systemctl daemon-reload
systemctl enable bazarr
systemctl restart bazarr

# Verificar el estado del servicio
if systemctl is-active --quiet bazarr; then
    log "INFO" "Bazarr se está ejecutando correctamente."
else
    log "ERROR" "Bazarr no se está ejecutando."
    journalctl -u bazarr --no-pager
    exit 1
fi

log "INFO" "Instalación y configuración de Bazarr completada."
