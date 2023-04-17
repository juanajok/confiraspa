#!/bin/sh

# Script Name: confiraspi
# Description: cript con los pasos para reinstalar la raspa
# Author: Juan José Hipólito
# Version: 2..0.0
# Date: 2023-03-30
# License: GNU
# Usage: Debes ejecutar el script desde la ruta donde estén los ficheros
#   dhcpcd.conf
#   settings.json
#   smb.conf
# Dependencies: No tiene
# Notes: Este script tiene como objetivo configurar una Raspberry Pi con varios servicios y programas, como Samba, XRDP, Transmission, Mono, Sonarr, Webmin, VNC, Plex, Bazarr y aMule. A continuación, se describen brevemente las funciones principales de cada uno de estos servicios y programas:

#Samba: Permite compartir archivos y directorios a través de una red local.
#XRDP: Habilita el acceso remoto al escritorio de la Raspberry Pi.
#Transmission: Cliente de torrent para descargar y compartir archivos.
#Mono: Entorno de desarrollo para ejecutar aplicaciones basadas en .NET.
#Sonarr: Gestiona automáticamente tus series de TV y descarga nuevos episodios.
#Webmin: Herramienta de administración de sistemas basada en web para Linux.
#VNC: Permite el control remoto gráfico de una Raspberry Pi.
#Plex: Servidor de medios para organizar y transmitir películas, series de TV y música.
#Bazarr: Permite la descarga automática de subtítulos para tus series y películas.
#aMule: Cliente P2P para compartir archivos a través de la red eD2k y Kademlia.

leer_credenciales() {
    usuario=$USER
    credenciales=$(cat credenciales.json)
    contrasena=$(echo "$credenciales" | jq -r '.password')
}

actualizar_raspi() {
    echo "1) Actualizando la Raspberry Pi..."
    sudo apt update && sudo apt upgrade -y && sudo apt dist-upgrade -y && sudo apt clean
    #instalo jq para tratar ficheros json
    sudo apt-get install jq -y
}

configurar_ip_estatica() {
  echo "2) Configurando IP estática..."

  # Leer la información de configuración desde el archivo JSON
  config=$(cat ip_config.json)

  # Asignar valores a las variables de configuración de IP
  interface=$(echo "$config" | jq -r '.interface')
  ip_address=$(echo "$config" | jq -r '.ip_address')
  routers=$(echo "$config" | jq -r '.routers')
  domain_name_servers=$(echo "$config" | jq -r '.domain_name_servers')

  # Hacer una copia de seguridad del archivo /etc/dhcpcd.conf
  sudo cp /etc/dhcpcd.conf /etc/dhcpcd.conf.old

  # Añadir la información de IP estática al final del archivo /etc/dhcpcd.conf
  echo "interface $interface" | sudo tee -a /etc/dhcpcd.conf
  echo "static ip_address=$ip_address" | sudo tee -a /etc/dhcpcd.conf
  echo "static routers=$routers" | sudo tee -a /etc/dhcpcd.conf
  echo "static domain_name_servers=$domain_name_servers" | sudo tee -a /etc/dhcpcd.conf
}

# Crea puntos de montaje
crear_puntos_de_montaje() {
    echo "3) Creando puntos de montaje..."
    sudo mkdir -p /media/discoduro && sudo chmod -R 777 /media/discoduro && sudo mkdir -p /media/Backup && sudo chmod -R 777 /media/Backup && sudo mkdir -p /media/WDElements && sudo chmod -R 777 /media/WDElements
}

generate_fstab() {
  # Asignamos las particiones
  particiones=$(lsblk -ln -o NAME,SIZE,TYPE,FSTYPE | grep -w 'part' | grep '^sd')
  sorted_partitions=$(echo "$particiones" | sort -k2 -h)

  discoduro_part=$(echo "$sorted_partitions" | head -n 1 | awk '{print $1}')
  discoduro_fstype=$(echo "$sorted_partitions" | head -n 1 | awk '{print $4}')
  backup_part=$(echo "$sorted_partitions" | tail -n 2 | head -n 1 | awk '{print $1}')
  backup_fstype=$(echo "$sorted_partitions" | tail -n 2 | head -n 1 | awk '{print $4}')
  wdelements_part=$(echo "$sorted_partitions" | tail -n 1 | awk '{print $1}')
  wdelements_fstype=$(echo "$sorted_partitions" | tail -n 1 | awk '{print $4}')

  # Imprimir los valores de las variables de particiones
  echo "discoduro_part: $discoduro_part"
  echo "discoduro_fstype: $discoduro_fstype"
  echo "backup_part: $backup_part"
  echo "backup_fstype: $backup_fstype"
  echo "wdelements_part: $wdelements_part"
  echo "wdelements_fstype: $wdelements_fstype"

  # Hacer una copia de seguridad del archivo /etc/fstab
  sudo cp /etc/fstab /etc/fstab.backup

  # Añadir las nuevas entradas al archivo /etc/fstab
  new_entries="/dev/$discoduro_part  /media/discoduro        $discoduro_fstype    defaults        0       0
/dev/$wdelements_part  /media/WDElements       $wdelements_fstype    defaults        0       0
/dev/$backup_part      /media/Backup           $backup_fstype    defaults        0       0"

  echo "$new_entries" | sudo tee -a /etc/fstab > /dev/null
}

instalar_samba() {
    echo "6) Instalando Samba..."
    sudo apt install -y samba samba-common-bin
    sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.old
    sudo cp smb.conf /etc/samba/smb.conf
    sudo systemctl restart smbd
}

instalar_xrdp() {
    echo "7) Instalando Escritorio Remoto (XRDP)..."
    sudo apt-get install -y xrdp
}

instalar_transmission() {
    echo "8) Instalando Transmission..."
    sudo apt-get install -y transmission-daemon
    sudo /etc/init.d/transmission-daemon stop
    sudo cp /var/lib/transmission-daemon/info/settings.json /var/lib/transmission-daemon/info/settings.json.old
    sudo cp settings.json /var/lib/transmission-daemon/info/settings.json
    sudo /etc/init.d/transmission-daemon start
}

instalar_mono() {
    echo "9) Instalando Mono..."
    sudo apt install -y apt-transport-https dirmngr gnupg ca-certificates
    sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF
    echo "deb https://download.mono-project.com/repo/debian stable-buster main" | sudo tee /etc/apt/sources.list.d/mono-official-stable.list
    sudo apt update
    sudo apt install mono-devel -y
}

instalar_sonarr() {
    echo "10) Instalando Sonarr..."
    sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 2009837CBFFD68F45BC180471F4F90DE2A9B4BF8
    echo "deb https://apt.sonarr.tv/debian buster main" | sudo tee /etc/apt/sources.list.d/sonarr.list
    sudo apt update
    sudo apt install -y sonarr
}


instalar_webmin() {
    # Descargar el script setup-repos.sh de Webmin
    echo "Descargando el script setup-repos.sh de Webmin..."
    curl -o setup-repos.sh https://raw.githubusercontent.com/webmin/webmin/master/setup-repos.sh

    # Ejecutar setup-repos.sh para configurar el repositorio oficial de Webmin
    echo "Configurando el repositorio oficial de Webmin..."
    sh setup-repos.sh

    # Instalar Webmin y sus dependencias
    echo "Instalando Webmin y sus dependencias..."
    sudo apt-get update
    sudo apt-get install webmin

    echo "Webmin instalado correctamente. Acceda a la interfaz de Webmin en https://[tu-ip]:10000"
}


habilitar_vnc(){
    # Habilitar el servidor VNC para que se ejecute al inicio
sudo systemctl enable vncserver-x11-serviced.service

# Iniciar el servidor VNC
sudo systemctl start vncserver-x11-serviced.service

# Mostrar el estado del servicio VNC para verificar que se ha iniciado correctamente
sudo systemctl status vncserver-x11-serviced.service

# Hacer una copia de seguridad del archivo /boot/config.txt
sudo cp /boot/config.txt /boot/config.txt.backup

# Eliminar las líneas que contienen hdmi_group y hdmi_mode si ya existen
sudo sed -i '/^hdmi_group=/d' /boot/config.txt
sudo sed -i '/^hdmi_mode=/d' /boot/config.txt

# Añadir las líneas al final del archivo /boot/config.txt para establecer la resolución de pantalla a 1280x720
echo "hdmi_group=2" | sudo tee -a /boot/config.txt
echo "hdmi_mode=85" | sudo tee -a /boot/config.txt
}

instalar_amule() {

# Instalar aMule, herramientas necesarias e interfaz gráfica
sudo apt-get update
sudo apt-get install -y amule amule-utils amule-daemon amule-utils-gui

# Iniciar el demonio de aMule para generar el archivo de configuración
sudo amuled

# Detener el demonio de aMule
sleep 5
sudo pkill -f amuled

# copia de seguridad de amule.conf
sudo cp /home/$usuario/.aMule/amule.conf /home/$usuario/.aMule/amule.conf.backup

# Rutas de directorios desde archivo JSON
directories_json="amule_directories.json"
incoming_directory=$(jq -r '.incoming_directory' "$directories_json")
temp_directory=$(jq -r '.temp_directory' "$directories_json")

# Cambiar rutas de directorios en amule.conf
amule_conf_path="/home/$usuario/.aMule/amule.conf"
sudo sed -i "s|^IncomingDir=.*$|IncomingDir=$incoming_directory|" "$amule_conf_path"
sudo sed -i "s|^TempDir=.*$|TempDir=$temp_directory|" "$amule_conf_path"
sudo sed -i "s|^Template=.*$|Template=webserver|" "$amule_conf_path"
sudo sed -i "s|^Password=.*$|Password=$(echo -n $contrasena | md5sum | awk '{ print $1 }')|" "$amule_conf_path"
sudo sed -i "s|^User=.*$|User=pi|" "$amule_conf_path"

# Configurar aMule para que se ejecute al iniciar la Raspberry Pi
sudo bash -c "cat > /etc/systemd/system/amule.service << EOL
[Unit]
Description=aMule Daemon
After=network.target

[Service]
User=$usuario
Type=forking
ExecStart=/usr/bin/amuled -f
ExecStop=/usr/bin/pkill -f amuled
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOL"

# Configurar aMule GUI para que se ejecute al iniciar la Raspberry Pi
sudo bash -c "cat > /etc/systemd/system/amule-gui.service << EOL
[Unit]
Description=aMule GUI
After=amule.service

[Service]
User=$usuario
Type=simple
ExecStart=/usr/bin/amule

[Install]
WantedBy=graphical.target
EOL"    

# reinicia el servicio para que coja los cambios
sudo systemctl daemon-reload
sudo systemctl enable amule.service
sudo systemctl enable amule-gui.service
sudo systemctl restart amule.service
sudo systemctl restart amule-gui.service

}

instalar_plex(){
    # Actualiza el sistema
sudo apt-get update -y
sudo apt-get upgrade -y

# Descarga e instala Plex Media Server
wget -O plex.deb https://downloads.plex.tv/plex-media-server-new/1.32.0.6918-6f393eda1/debian/plexmediaserver_1.32.0.6918-6f393eda1_armhf.deb?_gl=1*jybto6*_ga*MjY4NzExODIyLjE2ODE0MjY2NzI.*_ga_G6FQWNSENB*MTY4MTQyNjY3Mi4xLjEuMTY4MTQyNjkyMy4wLjAuMA..

sudo dpkg -i plex.deb

# Habilita e inicia Plex Media Server
sudo systemctl enable plexmediaserver.service
sudo systemctl start plexmediaserver.service

# Muestra la dirección IP del Raspberry Pi
echo "Plex Media Server instalado. Visita http://$(hostname -I | awk '{print $1}'):32400/web para configurarlo."
}

instalar_bazarr(){

# Instalar dependencias
sudo apt install -y python3 python3-pip python3-venv libffi-dev zlib1g-dev libicu-dev libxml2-dev libxslt1-dev g++ git

# Crear la carpeta de Bazarr
mkdir -p /home/$usuario/bazarr

# Clonar el repositorio de Bazarr en la carpeta
git clone https://github.com/morpheus65535/bazarr.git /home/$usuario/bazarr

# Navegar a la carpeta de Bazarr
cd /home/$usuario/bazarr

# Crear el entorno virtual de Python
python3 -m venv venv

# Activar el entorno virtual
source venv/bin/activate

# Instalar las dependencias de Bazarr
pip install -r requirements.txt

# Desactivar el entorno virtual
deactivate

# Crear el servicio de Bazarr
sudo bash -c "cat > /etc/systemd/system/bazarr.service << EOL
[Unit]
Description=Bazarr Daemon
After=syslog.target network.target

[Service]
User=$usuario
Group=$usuario
UMask=002
Type=simple
ExecStart=/home/$usuario/bazarr/venv/bin/python3 /home/$usuario/bazarr/bazarr.py
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
EOL"

# Habilitar y iniciar el servicio de Bazarr
sudo systemctl enable bazarr.service
sudo systemctl start bazarr.service

# Mostrar mensaje final
echo "Bazarr instalado. Visita http://<raspberry_pi_ip>:6767 para configurarlo."
}


main() {
    # Llamadas a las funciones
    actualizar_raspi
    leer_credenciales
    configurar_ip_estatica
    crear_puntos_de_montaje
    generate_fstab
    instalar_samba
    instalar_xrdp
    instalar_transmission
    instalar_mono
    instalar_sonarr
    instalar_webmin
    habilitar_vnc
    instalar_plex
    instalar_bazarr
    instalar_amule
}

main

