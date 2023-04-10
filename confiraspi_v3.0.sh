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
# Notes: NOTAS_ADICIONALES (si corresponde)

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
    sudo apt install apt-transport-https dirmngr gnupg ca-certificates
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
    sudo apt install sonarr
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

main() {
    # Llamadas a las funciones
    actualizar_raspi
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
}

main

