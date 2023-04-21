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

log() {
    #función que permitirá que los mensajes de salida identifiquen al script, la función y fecha/hora de ejecución
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$0] [${FUNCNAME[1]}] $message"
}


leer_credenciales() {
    usuario=$USER
    credenciales=$(cat credenciales.json)
    contrasena=$(echo "$credenciales" | jq -r '.password')
}


actualizar_raspi() {
    log "1) Actualizando la Raspberry Pi..."
    sudo apt update && sudo apt upgrade -y && sudo apt dist-upgrade -y && sudo apt autoremove -y && sudo apt clean
    #instalo jq para tratar ficheros json
    if ! command -v jq > /dev/null 2>&1; then
        sudo apt-get install jq -y
    fi
    # Comando de actualización semanal
    actualizacion_cmd="0 0 * * 1 sudo apt update && sudo apt upgrade -y && sudo apt dist-upgrade -y && sudo apt autoremove -y && sudo apt clean"
    # Añade el comando de actualización al crontab del usuario actual
    (crontab -l 2>/dev/null | grep -qF -- "$actualizacion_cmd") || (crontab -l 2>/dev/null; echo "$actualizacion_cmd") | crontab -
}


configurar_ip_estatica() {
  echo "2) Configurando IP estática..."

  if [ ! -f ip_config.json ]; then
      log "Error: No se encuentra el archivo ip_config.json. Asegúrate de que el archivo esté presente en la ruta donde estás ejecutando el script."
      exit 1
  fi

  # Leer la información de configuración desde el archivo JSON
  config=$(cat ip_config.json)

  # Asignar valores a las variables de configuración de IP
  interface=$(echo "$config" | jq -r '.interface')
  ip_address=$(echo "$config" | jq -r '.ip_address')
  routers=$(echo "$config" | jq -r '.routers')
  domain_name_servers=$(echo "$config" | jq -r '.domain_name_servers')

  # Hacer una copia de seguridad del archivo /etc/dhcpcd.conf si no existe previamente
  if [ ! -f /etc/dhcpcd.conf.backup ]; then
    sudo cp /etc/dhcpcd.conf /etc/dhcpcd.conf.backup
    log "copia de seguridad de /etc/dhcpcd.conf en /etc/dhcpcd.conf.backup"
  else
    log "el fichero /etc/dhcpcd.conf.backup ya existe. Se obvia el backup"
  fi

  # Añadir la información de IP estática al final del archivo /etc/dhcpcd.conf si no está presente
  if ! grep -P "^(?!#).*interface $interface" /etc/dhcpcd.conf; then
    log "Agregando 'interface $interface' al archivo /etc/dhcpcd.conf..."
    echo "interface $interface" | sudo tee -a /etc/dhcpcd.conf
  else
    log "'interface $interface' ya está presente en el archivo /etc/dhcpcd.conf."
  fi
  if ! grep -P "^(?!#).*static ip_address=$ip_address" /etc/dhcpcd.conf; then
    log "Agregando 'static ip_address=$ip_address' al archivo /etc/dhcpcd.conf..."
    echo "static ip_address=$ip_address" | sudo tee -a /etc/dhcpcd.conf
  else
    log "'static ip_address=$ip_address' ya está presente en el archivo /etc/dhcpcd.conf."
  fi
  if ! grep -P "^(?!#).*static routers=$routers" /etc/dhcpcd.conf; then
    log "Agregando 'static routers=$routers' al archivo /etc/dhcpcd.conf..."
    echo "static routers=$routers" | sudo tee -a /etc/dhcpcd.conf
  else
    log "'static routers=$routers' ya está presente en el archivo /etc/dhcpcd.conf."
  fi
  if ! grep -P "^(?!#).*static domain_name_servers=$domain_name_servers" /etc/dhcpcd.conf; then
    log "Agregando 'static domain_name_servers=$domain_name_servers' al archivo /etc/dhcpcd.conf..."
    echo "static domain_name_servers=$domain_name_servers" | sudo tee -a /etc/dhcpcd.conf
  else
    log "'static domain_name_servers=$domain_name_servers' ya está presente en el archivo /etc/dhcpcd.conf."
  fi
}

crear_puntos_de_montaje() {
    log "Iniciando la creación de puntos de montaje..."
    
    # Verificar si el archivo puntos_de_montaje.json existe
    if [ ! -f puntos_de_montaje.json ]; then
        log "Error: No se encuentra el archivo puntos_de_montaje.json. Asegúrate de que el archivo esté presente en la ruta donde estás ejecutando el script."
        exit 1
    else
        log "El archivo puntos_de_montaje.json ha sido encontrado."
    fi

    # Leer directorios del archivo JSON
    directorios=$(cat puntos_de_montaje.json | jq -r '.puntos_de_montaje | .[]')
    log "Leyendo directorios del archivo JSON."

    # Crear directorios y aplicar permisos
    for dir in "${directorios[@]}"; do
        if [ ! -d "$dir" ]; then
            sudo mkdir -p "$dir"
            log "Punto de montaje creado: $dir"
        else
            log "El punto de montaje $dir ya existe."
        fi
        sudo chmod -R 777 "$dir"
        log "Permisos aplicados: $dir"
    done

    log "Finalizando la creación de puntos de montaje..."
}

generate_fstab() {
  log "Iniciando la generación del archivo /etc/fstab..."

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
  log "discoduro_part: $discoduro_part"
  log "discoduro_fstype: $discoduro_fstype"
  log "backup_part: $backup_part"
  log "backup_fstype: $backup_fstype"
  log "wdelements_part: $wdelements_part"
  log "wdelements_fstype: $wdelements_fstype"

  # Hacer una copia de seguridad del archivo /etc/fstab
  if [ ! -f /etc/fstab.backup ]; then
    sudo cp /etc/fstab /etc/fstab.backup
    log "Copia de seguridad del archivo /etc/fstab creada."
  else
    log "La copia de seguridad del archivo /etc/fstab ya existe."
  fi

  # Añadir las nuevas entradas al archivo /etc/fstab
  new_entries="/dev/$discoduro_part  /media/discoduro        $discoduro_fstype    defaults        0       0
/dev/$wdelements_part  /media/WDElements       $wdelements_fstype    defaults        0       0
/dev/$backup_part      /media/Backup           $backup_fstype    defaults        0       0"

  # Comprobar si las entradas ya están presentes en /etc/fstab
  if ! grep -Fxq "$new_entries" /etc/fstab; then
    echo "$new_entries" | sudo tee -a /etc/fstab > /dev/null
    log "Nuevas entradas añadidas al archivo /etc/fstab."
  else
    log "Las entradas ya están presentes en el archivo /etc/fstab."
  fi

  log "Finalizando la generación del archivo /etc/fstab..."
}


instalar_samba() {
    log "6) Instalando Samba..."

    # Verificar si el paquete Samba ya está instalado
    if dpkg -s samba &> /dev/null; then
        log "Samba ya está instalado en el sistema."
        return
    fi

    # Instalar Samba
    log "Instalando samba"
    sudo apt install -y samba samba-common-bin

    # Hacer una copia de seguridad del archivo smb.conf original
    if [ ! -f /etc/samba/smb.conf.old ]; then
        sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.old
        log "Ejecutando copia de seguridad del fichero de configuración /etc/samba/smb.conf"
    fi

    # Copiar el archivo de configuración smb.conf
    sudo cp smb.conf /etc/samba/smb.conf
    log "fichero de configuración smb.conf modificado"

    # Reiniciar el servicio smbd
    log "reiniciando servicio de samba"
    sudo systemctl restart smbd

    log "Samba se ha instalado y configurado correctamente."
}

instalar_xrdp() {
    log "7) Instalando Escritorio Remoto (XRDP)..."
    
    # Verificar si XRDP ya está instalado
    if dpkg -s xrdp >/dev/null 2>&1; then
        log "XRDP ya está instalado en el sistema."
        return 0
    fi
    
    # Instalar XRDP
    sudo apt-get install -y xrdp
    
    log "XRDP instalado correctamente."
}

# Instalar Transmission
instalar_transmission() {
    log "8) Instalando Transmission..."

    # Verificar si el paquete transmission-daemon está instalado
    if ! dpkg -s transmission-daemon >/dev/null 2>&1; then
        log "El paquete transmission-daemon no está instalado. Instalando..."
        sudo apt-get install -y transmission-daemon
    else
        log "El paquete transmission-daemon ya está instalado. Continuando..."
    fi

    # Hacer una copia de seguridad del archivo de configuración de Transmission
    if [ -f /var/lib/transmission-daemon/info/settings.json ]; then
        sudo cp /var/lib/transmission-daemon/info/settings.json /var/lib/transmission-daemon/info/settings.json.old
        log "Copia de seguridad del archivo de configuración de Transmission creada: /var/lib/transmission-daemon/info/settings.json.old"
    else
        log "No se encontró el archivo de configuración de Transmission. Continuando..."
    fi

    # Copiar el archivo de configuración de Transmission al directorio de configuración de Transmission
    if [ -f settings.json ]; then
        sudo cp settings.json /var/lib/transmission-daemon/info/settings.json
        log "Archivo de configuración de Transmission copiado: /var/lib/transmission-daemon/info/settings.json"
    else
        log "No se encontró el archivo de configuración de Transmission. Continuando..."
    fi

    # Reiniciar el servicio de Transmission
    sudo service transmission-daemon restart
    log "Servicio de Transmission reiniciado."
}

instalar_mono() {
    log "9) Instalando Mono..."

    # Comprobar si Mono está instalado
    if dpkg -s mono-devel >/dev/null 2>&1; then
        log "Mono ya está instalado."
        return 0
    fi

    # Instalar Mono
    log "Instalando dependencias necesarias..."
    sudo apt install -y apt-transport-https dirmngr gnupg ca-certificates

    log "Añadiendo la clave de firma de Mono..."
    sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF

    log "Añadiendo el repositorio de Mono..."
    echo "deb https://download.mono-project.com/repo/debian stable-buster main" | sudo tee /etc/apt/sources.list.d/mono-official-stable.list

    log "Actualizando el índice de paquetes..."
    sudo apt update

    log "Instalando Mono..."
    sudo apt install -y mono-devel

    log "Mono instalado con éxito."
}


instalar_sonarr() {
    log "10) Instalando Sonarr..."

    # Verificar si Sonarr ya está instalado
    if dpkg -s sonarr > /dev/null 2>&1; then
        log "Sonarr ya está instalado, saltando..."
        return 0
    fi

    # Agregar la clave GPG de Sonarr
    log "Agregando clave GPG de Sonarr..."
    sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 2009837CBFFD68F45BC180471F4F90DE2A9B4BF8

    # Agregar el repositorio de Sonarr
    log "Agregando repositorio de Sonarr..."
    echo "deb https://apt.sonarr.tv/debian buster main" | sudo tee /etc/apt/sources.list.d/sonarr.list

    # Actualizar el índice de paquetes
    log "Actualizando el índice de paquetes..."
    sudo apt update

    # Instalar Sonarr
    log "Instalando Sonarr..."
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

instalar_webmin() {
    log "11) Instalando Webmin..."

    # Verificar si Webmin ya está instalado
    if dpkg-query -W -f='${Status}' webmin | grep -q "installed"; then
        log "Webmin ya está instalado en el sistema."
        return 0
    fi

    # Descargar el script setup-repos.sh de Webmin
    log "Descargando el script setup-repos.sh de Webmin..."
    curl -o setup-repos.sh https://raw.githubusercontent.com/webmin/webmin/master/setup-repos.sh

    # Ejecutar setup-repos.sh para configurar el repositorio oficial de Webmin
    log "Configurando el repositorio oficial de Webmin..."
    sh setup-repos.sh

    # Instalar Webmin y sus dependencias
    log "Instalando Webmin y sus dependencias..."
    sudo apt-get update
    sudo apt-get install -y webmin

    # Verificar si la instalación de Webmin fue exitosa
    if dpkg-query -W -f='${Status}' webmin | grep -q "installed"; then
        log "Webmin instalado correctamente. Acceda a la interfaz de Webmin en https://[tu-ip]:10000"
        return 0
    else
        log "Error: No se pudo instalar Webmin correctamente."
        return 1
    fi
}


habilitar_vnc() {
    log "11) Habilitando VNC..."

    # Verificar si el servicio VNC ya está habilitado
    if systemctl is-enabled vncserver-x11-serviced.service &> /dev/null; then
        log "El servicio VNC ya está habilitado. No es necesario hacer nada."
    else
        # Habilitar el servidor VNC para que se ejecute al inicio
        sudo systemctl enable vncserver-x11-serviced.service
        log "El servicio VNC ha sido habilitado para ejecutarse al inicio."

        # Iniciar el servidor VNC
        sudo systemctl start vncserver-x11-serviced.service
        log "El servicio VNC ha sido iniciado correctamente."

        # Mostrar el estado del servicio VNC para verificar que se ha iniciado correctamente
        sudo systemctl status vncserver-x11-serviced.service | grep -q 'active (running)' && log "El servicio VNC se ha iniciado correctamente." || (log "Error: No se ha podido iniciar el servicio VNC. Verifica la configuración." && exit 1)
    fi

    # Hacer una copia de seguridad del archivo /boot/config.txt
    sudo cp /boot/config.txt /boot/config.txt.backup
    log "Se ha creado una copia de seguridad del archivo /boot/config.txt."

    # Eliminar las líneas que contienen hdmi_group y hdmi_mode si ya existen
    if grep -qP '^(?!#)\s*hdmi_group=' /boot/config.txt && grep -qP '^(?!#)\s*hdmi_mode=' /boot/config.txt; then
        sudo sed -i '/^\s*hdmi_group=/d' /boot/config.txt
        sudo sed -i '/^\s*hdmi_mode=/d' /boot/config.txt
        log "Las líneas que contenían hdmi_group y hdmi_mode han sido eliminadas del archivo /boot/config.txt."
    fi

    # Añadir las líneas al final del archivo /boot/config.txt para establecer la resolución de pantalla a 1280x720
    echo -e "\nhdmi_group=2\nhdmi_mode=85" | sudo tee -a /boot/config.txt > /dev/null
    log "Se han añadido las líneas para establecer la resolución de pantalla a 1280x720 al final del archivo /boot/config.txt."
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

comandos_crontab(){
    # Leemos el archivo JSON y almacenamos la información en un array
    scripts_and_crontab=$(jq -c '.[]' scripts_and_crontab.json)

    # Aplicar permisos ejecutables y agregar al crontab de root
    for entry in $scripts_and_crontab; do
    script=$(echo "$entry" | jq -r '.script')
    crontab_entry=$(echo "$entry" | jq -r '.crontab_entry')

    # Aplicar permisos ejecutables
    chmod +x "$script"
    echo "Permisos ejecutables aplicados a: $script"

    # Comprobar si el script ya está en el crontab de root
    if sudo crontab -l | grep -q "$script"; then
        echo "El script $script ya está en el crontab de root."
    else
        # Agregar el script al crontab de root
        (sudo crontab -l 2>/dev/null; echo "$crontab_entry $script") | sudo crontab -
        echo "Script $script agregado al crontab de root."
    fi
    done
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
    comandos_crontab
}

main

