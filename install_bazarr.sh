#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Imprime un mensaje indicando que se están instalando las dependencias de Bazarr
log "Instalando dependencias de Bazarr..."

# Instala las dependencias de Bazarr
apt-get install -y libxml2-dev libxslt1-dev python3-dev python3-libxml2 python3-lxml unrar-free ffmpeg libatlas-base-dev

# Verifica si Python 3.8 es necesario y lo instala si es necesario
python_version=$(python3 -c "import sys; print('.'.join(map(str, sys.version_info[:2])))")
if [ "$(echo "$python_version < 3.7" | bc)" -eq 1 ]; then
    apt-get install -y python3.8
fi

# Verifica si unzip está instalado, si no, lo instala
if ! command -v unzip > /dev/null; then
    apt-get install -y unzip
fi

# Crea el directorio de instalación de Bazarr
mkdir -p /opt/bazarr

# Descarga y descomprime la última versión de Bazarr
wget -P /opt/bazarr https://github.com/morpheus65535/bazarr/releases/latest/download/bazarr.zip
unzip -d /opt/bazarr /opt/bazarr/bazarr.zip && rm /opt/bazarr/bazarr.zip

# Instala las dependencias de Python necesarias para Bazarr
python3 -m pip install -r /opt/bazarr/requirements.txt

# Si la arquitectura es armv6l, reinstala numpy
if [ "$(uname -m)" = "armv6l" ]; then
    python3 -m pip uninstall -y numpy && apt-get install -y python3-numpy
fi

# Establece permisos y propietario del directorio de Bazarr
chown -R $usuario:$app_guid /opt/bazarr
chmod -R 755 /opt/bazarr

# Crea el archivo de servicio para Bazarr
cat << EOF | tee /etc/systemd/system/bazarr.service
[Unit]
Description=Bazarr Daemon
After=syslog.target network.target

[Service]
WorkingDirectory=/opt/bazarr/
User=${usuario}
Group=${app_guid}
UMask=0002
Restart=on-failure
RestartSec=5
Type=simple
ExecStart=/usr/bin/python3 /opt/bazarr/bazarr.py
KillSignal=SIGINT
TimeoutStopSec=20
SyslogIdentifier=bazarr
ExecStartPre=/bin/sleep 30

[Install]
WantedBy=multi-user.target
EOF

# Inicia y habilita el servicio de Bazarr
systemctl start bazarr
systemctl enable bazarr

log "¡Bazarr ha sido instalado correctamente! Accede a la interfaz web en http://<raspberry_pi_ip>:6767"
