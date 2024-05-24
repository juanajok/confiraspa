#!/bin/bash

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


# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Función principal que coordina la ejecución de los scripts
main() {
    # Actualiza el sistema y asegura que las dependencias básicas están instaladas
    ./update_system.sh
    # Lee las credenciales y asegura que se está ejecutando como superusuario
    ./setup_credentials.sh
    # Configura una IP estática usando nmcli
    ./configure_static_ip.sh
    # Crea los puntos de montaje especificados en un archivo JSON
    ./create_mount_points.sh
    # Genera entradas para el archivo fstab
    ./generate_fstab.sh
    # Instala y configura Samba
    ./install_samba.sh
    # Instala y configura XRDP
    ./install_xrdp.sh
    # Instala y configura Transmission
    ./install_transmission.sh
    # Instala Mono
    ./install_mono.sh
    # Instala Sonarr
    ./install_sonarr.sh
    # Instala Webmin
    ./install_webmin.sh
    # Habilita VNC
    ./enable_vnc.sh
    # Instala Plex Media Server
    ./install_plex.sh
    # Instala y configura Bazarr
    ./install_bazarr.sh
    # Instala y configura aMule
    ./install_amule.sh
    # Configura las tareas programadas en crontab
    ./configure_crontab.sh

    log "Info: script finalizado, por favor reinicia para que los cambios tengan efecto"
}

# Llama a la función principal
main
