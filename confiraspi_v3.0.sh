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
}

configurar_ip_estatica() {
    echo "2) Configurando IP estática..."
    sudo mv /etc/dhcpcd.conf /etc/dhcpcd.conf.old
    sudo cp dhcpcd.conf /etc/dhcpcd.conf
}

# Crea puntos de montaje
crear_puntos_de_montaje() {
    echo "3) Creando puntos de montaje..."
    sudo mkdir -p /media/{discoduro,Backup,WDElements}
    sudo chmod -R 777 /media/{discoduro,Backup,WDElements}


generate_fstab() {
  # Obtener información de los dispositivos
  devices_info=$(lsblk -o NAME,FSTYPE,SIZE -b -n -P)

  # Encontrar las particiones correctas
  discoduro_part=$(echo "$devices_info" | awk -v min=1300000000000 -v max=1500000000000 '$3 >= min && $3 <= max {print $1}')
  backup_part=$(echo "$devices_info" | awk -v min=367000000000 -v max=407000000000 '$3 >= min && $3 <= max {print $1}')
  wdelements_part=$(echo "$devices_info" | awk -v min=3000000000000 -v max=4000000000000 '$3 >= min && $3 <= max {print $1}')

  # Crear el contenido del nuevo archivo /etc/fstab
  new_fstab_content="proc            /proc           proc    defaults          0       0
PARTUUID=24c53124-01  /boot           vfat    defaults          0       2
PARTUUID=24c53124-02  /               ext4    defaults,noatime  0       1
# a swapfile is not a swap partition, no line here
#   use  dphys-swapfile swap[on|off]  for that
/dev/$discoduro_part  /media/discoduro        ext4    defaults        0       0
/dev/$wdelements_part  /media/WDElements       ext4    defaults        0       0
/dev/$backup_part      /media/Backup           ext4    defaults        0       0"

  # Crear una copia de seguridad del archivo fstab actual
  sudo cp /etc/fstab /etc/fstab.backup

  # Escribir el nuevo contenido en /etc/fstab
  echo "$new_fstab_content" | sudo tee /etc/fstab

  # Montar todas las particiones según el nuevo archivo /etc/fstab
  sudo mount -a

  # Mostrar el contenido del nuevo archivo /etc/fstab
  cat /etc/fstab
}

instalar_samba() {
    echo "6) Instalando Samba..."
    sudo apt install -y samba samba-common-bin
    sudo mv /etc/samba/smb.conf /etc/samba/smb.conf.old
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
    sudo mv /var/lib/transmission-daemon/info/settings.json /var/lib/transmission-daemon/info/settings.json.old
    sudo cp settings.json /var/lib/transmission-daemon/info/settings.json
    sudo /etc/init.d/transmission-daemon start
}

instalar_mono() {
    echo "9) Instalando Mono..."
    sudo apt install apt-transport-https dirmngr -y
    sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF
    echo "deb https://download.mono-project.com/repo/debian stable-raspbianstretch main" | sudo tee /etc/apt/sources.list.d/mono-official-stable.list
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

ejecutar_arrinstal() {
    echo "Ejecutando el script Arrinstal.sh..."
    if [ -f Arrinstal.sh ]; then
        sh Arrinstal.sh
    else
        echo "No se encontró el archivo Arrinstal.sh en el directorio actual. Asegúrate de que esté presente y vuelve a intentarlo."
        exit 1
    fi
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
ejecutar_arrinstal.sh