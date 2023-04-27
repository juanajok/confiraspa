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
}



instalar_bazarr() {

    leercredenciales

    log "Instalando dependencias de Bazarr..."
    sudo sudo apt-get install libxml2-dev libxslt1-dev python3-dev python3-libxml2 python3-lxml unrar-free ffmpeg libatlas-base-dev


    log "Creando la carpeta de Bazarr..."
    mkdir -p /opt/bazarr
    chown -R $usuario:$usuario /opt/bazarr
    chmod 755 /opt/bazarr

    if [ ! -d "/opt/bazarr/.git" ]; then
        log "Clonando el repositorio de Bazarr en la carpeta..."
        git clone https://github.com/morpheus65535/bazarr/releases/latest/download/bazarr.zip /opt/bazarr
    else
        log "El repositorio de Bazarr ya está clonado. No es necesario clonarlo de nuevo."
    fi
    chmod 777 /opt/bazarr


    log "Navegando a la carpeta de Bazarr..."
    cd /opt/bazarr

    if [ ! -d "venv" ]; then
        log "Creando el entorno virtual de Python..."
        python3 -m venv venv
    else
        log "El entorno virtual de Python ya existe. No es necesario crearlo de nuevo."
    fi

    log "Activando el entorno virtual y actualizando las dependencias de Bazarr..."
    source venv/bin/activate
    pip install -r requirements.txt
    deactivate

    if [ ! -f "/etc/systemd/system/bazarr.service" ]; then
        log "Creando el servicio de Bazarr..."
        sudo bash -c "cat > /etc/systemd/system/bazarr.service << EOL
[Unit]
Description=Bazarr Daemon
After=syslog.target network.target

[Service]
User=$usuario
Group=$app_guid
UMask=002
Type=simple
ExecStart=/opt/bazarr/venv/bin/python3 /opt/bazarr/bazarr.py
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
EOL"
    else
        log "El servicio de Bazarr ya existe. No es necesario crearlo de nuevo."
    fi

    log "Habilitando e iniciando el servicio de Bazarr..."
    sudo systemctl enable bazarr.service
    sudo systemctl start bazarr.service
    sudo systemctl status bazarr.service


    log "Bazarr instalado. Visita http://<raspberry_pi_ip>:6767 para configurarlo."
    #volvemos al directorio donde está el script
    cd "$script_path"
}

instalar_bazarr