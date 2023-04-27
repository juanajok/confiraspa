#!/bin/bash

# Actualizar repositorios e instalar paquetes necesarios
sudo apt-get update
sudo apt-get install -y libxml2-dev libxslt1-dev python3-dev python3-libxml2 python3-lxml unrar-free ffmpeg libatlas-base-dev

# Comprobar versión de Python instalada y actualizar si es necesario
python_version=$(python3 -c "import sys; print('.'.join(map(str, sys.version_info[:2])))")
if [ "$(echo "$python_version >= 3.7" | bc)" -eq 0 ]; then
  echo "Python $python_version no es compatible, se requiere versión 3.7 o superior. Actualizando Python..."
  sudo apt-get install -y python3.8
fi

# Descargar y descomprimir Bazarr
csudo mkdir -p /opt/bazarr
sudo wget -P /opt/bazarr https://github.com/morpheus65535/bazarr/releases/latest/download/Bazarr-linux64.zip
sudo unzip -d /opt/bazarr Bazarr-linux64.zip
sudo rm /opt/bazarr/Bazarr-linux64.zip


# Instalar requisitos de Python
sudo python3 -m pip install -r requirements.txt

# En Raspberry Pi antiguas (ARMv6) numpy no es compatible
if [ "$(uname -m)" = "armv6l" ]; then
  echo "Raspberry Pi antigua detectada. Reemplazando numpy..."
  sudo python3 -m pip uninstall -y numpy
  sudo apt-get install -y python3-numpy
fi

# Cambiar propiedad de la carpeta de Bazarr al usuario deseado
sudo chown -R $USER:$USER /opt/bazarr

# Crear el archivo de servicio de systemd
sudo bash -c 'cat << EOF > /etc/systemd/system/bazarr.service
[Unit]
Description=Bazarr Daemon
After=syslog.target network.target

[Service]
WorkingDirectory=/opt/bazarr/
User=$USER
Group=$USER
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
EOF'

# Iniciar y habilitar el servicio
sudo systemctl start bazarr
sudo systemctl enable bazarr
