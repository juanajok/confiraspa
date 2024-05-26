#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message"
}

log "Instalando dependencias de Bazarr..."

# Instalar dependencias necesarias para Bazarr
sudo apt-get install -y libxml2-dev libxslt1-dev python3-dev python3-libxml2 python3-lxml unrar-free ffmpeg libatlas-base-dev python3-venv

# Verificar si unzip está instalado, si no, lo instala
if ! command -v unzip > /dev/null; then
    sudo apt-get install -y unzip
fi

# Crear directorio para Bazarr
log "Creando directorio para Bazarr..."
sudo mkdir -p /opt/bazarr

# Descargar y descomprimir Bazarr
log "Descargando y descomprimiendo Bazarr..."
sudo wget -P /opt/bazarr https://github.com/morpheus65535/bazarr/releases/latest/download/bazarr.zip
sudo unzip -d /opt/bazarr /opt/bazarr/bazarr.zip
sudo rm /opt/bazarr/bazarr.zip

# Crear entorno virtual
log "Creando entorno virtual para Bazarr..."
sudo python3 -m venv /opt/bazarr/venv

# Activar entorno virtual e instalar dependencias de Bazarr
log "Instalando dependencias de Bazarr en el entorno virtual..."
sudo /opt/bazarr/venv/bin/pip install -r /opt/bazarr/requirements.txt

# Si la arquitectura es armv6l, reinstala numpy
if [ "$(uname -m)" = "armv6l" ]; then
    sudo /opt/bazarr/venv/bin/pip uninstall -y numpy
    sudo apt-get install -y python3-numpy
fi

# Establecer permisos y propietario adecuados
log "Estableciendo permisos para Bazarr..."
sudo chown -R $USER:$USER /opt/bazarr
sudo chmod -R 755 /opt/bazarr

# Crear archivo de servicio systemd para Bazarr
log "Creando archivo de servicio systemd para Bazarr..."
cat << EOF | sudo tee /etc/systemd/system/bazarr.service
[Unit]
Description=Bazarr Daemon
After=syslog.target network.target

[Service]
WorkingDirectory=/opt/bazarr
User=$USER
Group=$USER
UMask=0002
Restart=on-failure
RestartSec=5
Type=simple
ExecStart=/opt/bazarr/venv/bin/python /opt/bazarr/bazarr.py
KillSignal=SIGINT
TimeoutStopSec=20
SyslogIdentifier=bazarr
ExecStartPre=/bin/sleep 30

[Install]
WantedBy=multi-user.target
EOF

# Habilitar y arrancar el servicio Bazarr
log "Habilitando y arrancando el servicio Bazarr..."
sudo systemctl daemon-reload
sudo systemctl enable bazarr
sudo systemctl start bazarr

# Verificar el estado del servicio
log "Verificando el estado del servicio Bazarr..."
sudo systemctl status bazarr

log "Instalación y configuración de Bazarr completada."
