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
    if [ "$EUID" -ne 0 ]
    then
        log "Error: Por favor, ejecuta el script como superusuario (sudo)."
        exit 1
    fi

    usuario="$SUDO_USER"
    app_guid=$(id -gn "$usuario")

    credenciales=$(cat credenciales.json)
    contrasena=$(echo "$credenciales" | jq -r '.password')
    log "Info:  Se usuará el usuario $usuario que corre este script como credenciales para el resto de instaciones"
    ruta_instalacion=
    script_path="$(dirname "$(realpath "$0")")"
}


actualizar_raspi() {
    log "1) Actualizando la Raspberry Pi..."
    sudo apt update && sudo apt upgrade -y && sudo apt dist-upgrade -y && sudo apt autoremove -y && sudo apt clean
    #instalo jq para tratar ficheros json
    if ! command -v jq > /dev/null 2>&1; then
        sudo apt-get install jq -y
        sudo apt-get install -y moreutils
    fi
    # Comando de actualización semanal
    actualizacion_cmd="0 0 * * 1 sudo apt update && sudo apt upgrade -y && sudo apt dist-upgrade -y && sudo apt autoremove -y && sudo apt clean"
    # Añade el comando de actualización al crontab del usuario actual
    (crontab -l 2>/dev/null | grep -qF -- "$actualizacion_cmd") || (crontab -l 2>/dev/null; echo "$actualizacion_cmd") | crontab -
}


configurar_ip_estatica() {
    log "Configurando IP estática usando nmcli..."

    # Verificar si 'jq' está instalado
    if ! command -v jq > /dev/null; then
        log "Error: 'jq' es necesario para este script. Instálalo con 'sudo apt-get install jq'."
        return 1
    fi

    # Leer la configuración de red desde el archivo JSON
    if [ ! -f network_config.json ]; then
        log "Error: El archivo network_config.json no se encuentra. Asegúrate de que el archivo esté presente en la ruta donde estás ejecutando el script."
        return 1
    fi

    local config=$(cat network_config.json)
    # Validar el formato JSON
    if ! echo "$config" | jq empty; then
        log "Error: Formato JSON inválido en network_config.json."
        return 1
    fi

    local CONEXION=$(echo "$config" | jq -r '.conexion')
    local IP_ESTATICA=$(echo "$config" | jq -r '.ip_estatica')
    local GATEWAY=$(echo "$config" | jq -r '.gateway')
    local DNS=$(echo "$config" | jq -r '.dns')
    local MASCARA=$(echo "$config" | jq -r '.mascara')

    # Verifica la existencia de la conexión
    if ! nmcli con show | grep -q "$CONEXION"; then
        log "Error: La conexión $CONEXION no existe."
        return 1
    fi

    # Encuentra el nombre del dispositivo asociado con esta conexión
    NOMBRE_DISPOSITIVO=$(nmcli -t -f DEVICE con show "$CONEXION")
    if [ -z "$NOMBRE_DISPOSITIVO" ]; then
        log "Error: No se pudo encontrar el dispositivo para la conexión $CONEXION."
        return 1
    fi

    # Aplica la configuración a la conexión
    if nmcli con mod "$CONEXION" ipv4.addresses "$IP_ESTATICA/$MASCARA" &&
       nmcli con mod "$CONEXION" ipv4.gateway "$GATEWAY" &&
       nmcli con mod "$CONEXION" ipv4.dns "$DNS" &&
       nmcli con mod "$CONEXION" ipv4.method manual; then

        # Reinicia la conexión de red para aplicar los cambios
        #nmcli device disconnect "$NOMBRE_DISPOSITIVO" && nmcli device connect "$NOMBRE_DISPOSITIVO"
        log "Configuración de IP estática aplicada a la conexión $CONEXION"
    else
        log "Error al aplicar la configuración a la conexión $CONEXION"
        return 1
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

instalar_transmission() {
    log "8) Instalando Transmission..."

    # Verificar si el paquete transmission-daemon está instalado
    if ! dpkg -s transmission-daemon >/dev/null 2>&1; then
        log "El paquete transmission-daemon no está instalado. Instalando..."
        sudo apt-get install -y transmission-daemon
    else
        log "El paquete transmission-daemon ya está instalado. Continuando..."
    fi

    # paramos el servicio de transmission para poder modificar el fichero de configuración
    sudo service transmission-daemon stop

    # Hacer una copia de seguridad del archivo de configuración de Transmission
    CONFIG_FILE="/var/lib/transmission-daemon/info/settings.json"
    if [ -f $CONFIG_FILE ]; then
    sudo jq --arg temp_dir "$TEMP_DIR" --arg download_dir "$DOWNLOAD_DIR" \
    '.["incomplete-dir"]=$temp_dir | .["download-dir"]=$download_dir | .["rpc-username"]="transmission" | .["rpc-password"]="transmission" | .["rpc-whitelist-enabled"]=true | .["rpc-whitelist"]="192.168.*.*"' $CONFIG_FILE | sudo sponge $CONFIG_FILE
    else
        log "No se encontró el archivo de configuración de Transmission. Continuando..."
    fi

    # Leer el directorio temporal y el directorio de descargas completadas de amule_directories.json
    if [ -f amule_directories.json ]; then
        TEMP_DIR=$(jq -r '.temp_directory' amule_directories.json)
        DOWNLOAD_DIR=$(jq -r '.incoming_directory' amule_directories.json)
    else
        log "No se encontró el archivo amule_directories.json. "
        exit
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
    log "Instalando aMule y sus dependencias..."

    # Instalar aMule, herramientas necesarias e interfaz gráfica
    sudo apt-get update
    sudo apt-get install -y amule amule-utils amule-daemon amule-utils-gui
    log "aMule y sus dependencias instaladas correctamente."

  
    # Iniciar el demonio de aMule para generar el archivo de configuración
    log "Iniciando el demonio de aMule para generar el archivo de configuración..."
    sudo -u $usuario bash -c "amuled --ec-config <<< \"$contrasena\"" &

    #Detener el demonio de aMule
    sleep 20
    sudo pkill -f amuled
    log "El demonio de aMule ha sido detenido."
    
    #volvemos al directorio donde está el script
    cd "$script_path"

    # copia de seguridad de amule.conf
    sudo cp /home/$usuario/.aMule/amule.conf /home/$usuario/.aMule/amule.conf.backup
    log "Copia de seguridad de amule.conf creada."

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
    sudo sed -i "s|^AcceptExternalConnections=.*$|AcceptExternalConnections=1|" "$amule_conf_path"
    #Habilitamos conexiones externas a través del puerto 4711
    sudo sed -i "/^\[WebServer\]/,/^\[/ s|^Enabled=.*$|Enabled=1|" "$amule_conf_path"
    sudo sed -i "/^\[WebServer\]/,/^\[/ s|^Port=.*$|Port=4711|" "$amule_conf_path"
    # Establecer contraseña cifrada para conexiones externas
    sudo sed -i "s|^ECPassword=.*$|ECPassword=$(echo -n $contrasena | md5sum | awk '{ print $1 }')|" "$amule_conf_path"

    log "Se han actualizado las rutas de directorios y la configuración en amule.conf."

    # Configurar aMule para que se ejecute al iniciar la Raspberry Pi
    log "Configurando aMule para que se ejecute al iniciar la Raspberry Pi..."
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
    log "Configurando aMule GUI para que se ejecute al iniciar la Raspberry Pi..."
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

    log "aMule y aMule GUI configurados para ejecutarse al inicio."

    # Reinicia el servicio para que coja los cambios
    log "Reiniciando servicios de aMule y aMule GUI..."
    sudo systemctl daemon-reload
    sudo systemctl enable amule.service
    sudo systemctl enable amule-gui.service
    sudo systemctl restart amule.service
    sudo systemctl restart amule-gui.service
    log "Servicios de aMule y aMule GUI reiniciados correctamente."
}


instalar_plex() {
    log "Instalando Plex Media Server..."

    # Actualiza el sistema
    log "Actualizando el sistema..."
    sudo apt-get update -y
    sudo apt-get upgrade -y

    # Verifica si Plex ya está instalado
    if ! dpkg -s plexmediaserver >/dev/null 2>&1; then
        # Descarga e instala Plex Media Server
        log "Descargando Plex Media Server..."
        wget -O plex.deb https://downloads.plex.tv/plex-media-server-new/1.32.0.6918-6f393eda1/debian/plexmediaserver_1.32.0.6918-6f393eda1_armhf.deb?_gl=1*jybto6*_ga*MjY4NzExODIyLjE2ODE0MjY2NzI.*_ga_G6FQWNSENB*MTY4MTQyNjY3Mi4xLjEuMTY4MTQyNjkyMy4wLjAuMA..

        log "Instalando Plex Media Server..."
        sudo dpkg -i plex.deb
        rm plex.deb
    else
        log "Plex Media Server ya está instalado."
    fi

    # Habilita e inicia Plex Media Server si no está activo
    if ! systemctl is-active --quiet plexmediaserver.service; then
        log "Habilitando e iniciando Plex Media Server..."
        sudo systemctl enable plexmediaserver.service
        sudo systemctl start plexmediaserver.service
    else
        log "Plex Media Server ya está habilitado e iniciado."
    fi

    # Muestra la dirección IP del Raspberry Pi
    log "Plex Media Server instalado. Visita http://$(hostname -I | awk '{print $1}'):32400/web para configurarlo."
}


instalar_bazarr() {

    #nstalar paquetes necesarios
    log "Instalando dependencias de Bazarr..."
    apt-get install -y libxml2-dev libxslt1-dev python3-dev python3-libxml2 python3-lxml unrar-free ffmpeg libatlas-base-dev -y

    # Comprobar versión de Python instalada y actualizar si es necesario
    python_version=$(python3 -c "import sys; print('.'.join(map(str, sys.version_info[:2])))")
    if [ "$(echo "$python_version < 3.7" | bc)" -eq 1 ]; then
    log  "Python $python_version no es compatible, se requiere versión 3.7 o superior. Actualizando Python..."
    apt-get install -y python3.8
    fi

    # Descargar y descomprimir Bazarr
    log "Creando la carpeta de Bazarr..."
    mkdir -p /opt/bazarr
    log "Descargando el repositorio de Bazarr ..."
    wget -P /opt/bazarr https://github.com/morpheus65535/bazarr/releases/latest/download/bazarr.zip
    log "Descomprimiendo el repositorio de Bazarr en la carpeta..."
    unzip -d /opt/bazarr /opt/bazarr/bazarr.zip
    rm /opt/bazarr/bazarr.zip

    # Instalar requisitos de Python""
    log "Instalando los requisitos de Python..."
    python3 -m pip install -r /opt/bazarr/requirements.txt

    # En Raspberry Pi antiguas (ARMv6) numpy no es compatible
    if [ "$(uname -m)" = "armv6l" ]; then
    log "Raspberry Pi antigua detectada. Reemplazando numpy..."
    python3 -m pip uninstall -y numpy
    apt-get install -y python3-numpy
    fi

    # Cambiar propiedad de la carpeta de Bazarr al usuario deseado
    log " Cambiando propiedad y permisos de la carpeta de Bazarr..."
    chown -R $usuario:$app_guid /opt/bazarr
    chmod -R 777 /opt/bazarr


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
    log "Habilitando e iniciando el servicio de Bazarr..."
    sudo systemctl start bazarr
    sudo systemctl enable bazarr
    sudo systemctl status bazarr

    # Mensaje de confirmación y enlace para acceder a la interfaz web de Bazarr
    log "¡Bazarr ha sido instalado correctamente!"
    log "Accede a la interfaz web en http://<raspberry_pi_ip>:6767"
}

instalar_rclone(){
    log "Instalamos rclone para hacer sincronizar discos duros con la nube"

    # Define the URL for the latest rclone
    if [ "$1" = "beta" ]; then
        download_link="https://beta.rclone.org/rclone-beta-latest-linux-arm.zip"
    else
        download_link="https://downloads.rclone.org/rclone-current-linux-arm.zip"
    fi

    # Create a temporary directory and change to it
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir"

    # Download and unzip rclone
    log "Downloading rclone..."
    curl -OfsS "$download_link"
    log "Unzipping rclone..."
    unzip -a *.zip -d rclone_tmp

    # Check if rclone is already installed
    if command -v rclone &>/dev/null; then
        log "rclone is already installed, checking for updates..."
        current_version=$(rclone --version | head -n 1)
        latest_version=$(rclone_tmp/*/rclone --version | head -n 1)
        if [ "$current_version" = "$latest_version" ]; then
            log "rclone is up-to-date."
            rm -r "$tmp_dir"
            exit 0
        else
            log "Updating rclone..."
        fi
    else
        log "Installing rclone..."
    fi

    # Move rclone to your $PATH
    sudo cp rclone_tmp/*/rclone /usr/bin/
    sudo chown root:root /usr/bin/rclone
    sudo chmod 755 /usr/bin/rclone

    # Check if mandb command is available for manpage installation
    if [ -x "$(command -v mandb)" ]; then
        log "Installing rclone manpage..."
        sudo mkdir -p /usr/local/share/man/man1
        sudo cp rclone_tmp/*/rclone.1 /usr/local/share/man/man1/
        sudo mandb
    fi

    # Clean up
    rm -r "$tmp_dir"

    log "rclone has been installed. Run 'rclone config' to start setup."
}

setup_logrotate_from_json() {

    # Directorio donde se encuentran los logs
    LOG_DIR="$(pwd)/logs"

    # Archivo de configuración de los trabajos en formato JSON
    JOBS_CONFIG="logrotate_jobs_config.json"

    # Archivo de configuración de logrotate
    LOGROTATE_CONFIG="/etc/logrotate.d/my_jobs"

    # Verificar si el archivo jobs_config.json existe
    if [ ! -f "$JOBS_CONFIG" ]; then
        log "El archivo $JOBS_CONFIG no existe."
        exit 1
    fi

    # Comprobar si el archivo de configuración de logrotate ya existe
    if [ -f "$LOGROTATE_CONFIG" ]; then
        log "El archivo de configuración de logrotate ya existe. Saliendo para evitar sobrescribir."
        exit 0
    fi

    log "Generando configuración de logrotate..."

    # Leer el archivo jobs_config.json y generar la configuración de logrotate
    length=$(jq '. | length' "$JOBS_CONFIG")
    for (( i=0; i<$length; i++ )); do
        job=$(jq -r ".[$i].job" "$JOBS_CONFIG")
        days=$(jq -r ".[$i].days" "$JOBS_CONFIG")

        cat <<EOL >> "$LOGROTATE_CONFIG"
$LOG_DIR/${job}_*.log {
    daily
    rotate $days
    compress
    missingok
    notifempty
    create 0644 $usuario $usuario
}
EOL
done

    log "Configuración de logrotate generada en $LOGROTATE_CONFIG"

}

comandos_crontab() {
    log "Configurando comandos de crontab..."
    #volvemos al directorio donde está el script
    cd "$script_path"

    # Reemplaza el marcador de posición por el valor de la variable $script_path
    json_data=$(sed "s@SCRIPT_PATH_PLACEHOLDER@$script_path@g" scripts_and_crontab.json)

    # Itera sobre el array de objetos JSON y ejecuta el cuerpo del bucle para cada objeto
    echo "$json_data" | jq -c '.[]' | while read -r entry; do
        script=$(echo "$entry" | jq -r '.script')
        crontab_entry=$(echo "$entry" | jq -r '.crontab_entry')

        # Aplicar permisos ejecutables
        log "Aplicando permisos ejecutables a $script..."
        chmod +x "$script"

        # Comprobar si el script ya está en el crontab de root
        if sudo crontab -l | grep -q "$script"; then
            log "El script $script ya está en el crontab de root."
        else
            # Agregar el script al crontab de root
            log "Agregando el script $script al crontab de root..."
            (sudo crontab -l 2>/dev/null; echo "$crontab_entry $script") | sudo crontab -
        fi
    done

    log "Configuración de comandos de crontab completada."
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
    instalar_rclone
    setup_logrotate_from_json
    comandos_crontab
    log "Info: script finalizado, por favor reinicia para que los cambios tengan efecto"
}

main
