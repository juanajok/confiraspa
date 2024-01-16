#!/bin/bash

usuario="$SUDO_USER"
app_guid=$(id -gn "$usuario")

# Cambiar a usuario root

# Actualizar repositorios e instalar paquetes necesarios
apt-get install -y libxml2-dev libxslt1-dev python3-dev python3-libxml2 python3-lxml ffmpeg libatlas-base-dev python3-pip python3-distutils unrar unzip -y

# Comprobar versión de Python instalada y actualizar si es necesario
python_version=$(python3 -c "import sys; print('.'.join(map(str, sys.version_info[:2])))")
if [ "$(echo "$python_version < 3.7" | bc)" -eq 1 ]; then
  echo "Python $python_version no es compatible, se requiere versión 3.7 o superior. Actualizando Python..."
  apt-get install -y python3.8
fi

# Descargar y descomprimir Bazarr
mkdir -p /opt/bazarr
wget -P /opt/bazarr https://github.com/morpheus65535/bazarr/releases/latest/download/bazarr.zip
unzip -d /opt/bazarr /opt/bazarr/bazarr.zip
rm /opt/bazarr/bazarr.zip

# Cambiar propiedad de la carpeta de Bazarr al usuario deseado
chown -R $usuario:$app_guid /opt/bazarr
chmod -R 777 /opt/bazarr

# Crea un entorno virtual
cd /opt/bazarr
python3 -m venv myenv
source myenv/bin/activate
# Instala las dependencias de Bazarr
pip install -r requirements.txt

# Desactiva el entorno virtual
deactivate



# Crear el archivo de servicio de systemd
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

# Iniciar y habilitar el servicio
sudo systemctl start bazarr
sudo systemctl enable bazarr
sudo systemctl status bazarr

# Mensaje de confirmación y enlace para acceder a la interfaz web de Bazarr
echo "¡Bazarr ha sido instalado correctamente!"
echo "Accede a la interfaz web en http://<raspberry_pi_ip>:6767"

# Salir del script
exit 0