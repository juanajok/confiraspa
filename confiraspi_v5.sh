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
main() {    # Añadir permisos de ejecución a todos los scripts
    log "Asignando permisos de ejecución a los scripts..."
    chmod +x /opt/confiraspa/*.sh
    # Actualiza el sistema y asegura que las dependencias básicas están instaladas
    log "1) Actualizando el sistema..."
    ./update_system.sh

    # Lee las credenciales y asegura que se está ejecutando como superusuario
    log "2) Configurando las credenciales..."
    ./setup_credentials.sh

    # Configura una IP estática usando nmcli
    #./configure_static_ip.sh

    # Crea los puntos de montaje especificados en un archivo JSON
    log "4) Creando puntos de montaje..."
    ./create_mount_points.sh

    
    # Genera entradas para el archivo fstab
    log "5) Generando fstab..."
    ./generate_fstab.sh

    # Instala y configura Samba
    log "6) Instalando Samba..."
    ./install_samba.sh

    # Instala y configura XRDP
    log "7) Instalando XRDP..."
    ./install_xrdp.sh

    # Instala y configura Transmission
    log "8) Instalando Transmission..."
    ./install_transmission.sh

    # Instala Mono
    log "9) Instalando Mono..."
    ./install_mono.sh

    # Instala Sonarr
    log "10) Instalando Sonarr..."
    ./install_sonarr.sh

    # Instala Webmin
    log "11) Instalando Webmin..."
    ./install_webmin.sh

    # Habilita VNC
    log "12) Habilitando VNC..."
    ./enable_vnc.sh

    # Instala Plex Media Server
    log "13) Instalando Plex..."
    ./install_plex.sh

    # Instala y configura Bazarr
    log "14) Instalando Bazarr..."
    ./install_bazarr.sh

    # Instala y configura aMule
    log "15) Instalando aMule..."
    ./install_amule.sh

    # Configura las tareas programadas en crontab
    log "16) Configurando crontab..."
    ./configure_crontab.sh

    # Instala y configura RClone
    log "16) Instalando RClone..."
    install_rclone.sh

    # Configura el rotado de logs
    log "16) Instalando RClone..."
    setup_logrotate_from_json.sh
    
    log "Info: script finalizado, por favor reinicia para que los cambios tengan efecto"
}

# Llama a la función principal
main
