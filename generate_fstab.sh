#!/bin/bash

# Script Name: configure_fstab.sh
# Description: Este script configura el archivo /etc/fstab para montar particiones específicas en directorios designados. Crea copias de seguridad del archivo original, verifica la existencia de las particiones y añade nuevas entradas para su montaje automático.
# Author: [Tu Nombre]
# Version: 1.0.0
# Date: [Fecha de Creación]
# License: MIT License
# Usage: Ejecutar este script con privilegios de superusuario (sudo).
# Requirements: blkid, mount
# Notes:
#   - El script verifica que se ejecute como root antes de proceder.
#   - Crea una copia de seguridad del archivo /etc/fstab antes de realizar cambios.
#   - Añade entradas de montaje al archivo /etc/fstab solo si las particiones necesarias están disponibles.
#   - Revierta los cambios si ocurre un error al montar las nuevas entradas.
# Dependencies:
#   - blkid: Utilizado para obtener UUIDs y tipos de sistemas de archivos de las particiones.
#   - mount: Utilizado para probar las nuevas entradas en el archivo /etc/fstab.
# Important: Este script debe ser ejecutado con privilegios de superusuario (sudo).

set -e

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message"
}

# Verificar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    log "Este script debe ser ejecutado con privilegios de superusuario (sudo)."
    exit 1
fi

log "Iniciando la configuración del archivo /etc/fstab..."

# Crear una copia de seguridad del archivo fstab si no existe
if [ ! -f /etc/fstab.backup ]; then
    cp /etc/fstab /etc/fstab.backup
    log "Copia de seguridad del archivo /etc/fstab creada."
else
    log "La copia de seguridad del archivo /etc/fstab ya existe."
fi

# Crear puntos de montaje
mkdir -p /media/discoduro /media/Backup /media/WDElements
log "Directorios de montaje creados."

# Obtener UUIDs de las particiones por etiqueta
get_uuid_by_label() {
    local label="$1"
    blkid -L "$label" 2>/dev/null
}

# Asignar variables para cada partición
discoduro_device=$(get_uuid_by_label "DiscoDuro")
backup_device=$(get_uuid_by_label "Backup")
wdelements_device=$(get_uuid_by_label "WDElements")

# Verificar que las particiones existen
if [ -z "$discoduro_device" ] || [ -z "$backup_device" ] || [ -z "$wdelements_device" ]; then
    log "Error: No se pudieron encontrar todas las particiones necesarias."
    exit 1
fi

# Obtener UUIDs
discoduro_uuid=$(blkid -s UUID -o value "$discoduro_device")
backup_uuid=$(blkid -s UUID -o value "$backup_device")
wdelements_uuid=$(blkid -s UUID -o value "$wdelements_device")

# Obtener sistemas de archivos
discoduro_fstype=$(blkid -s TYPE -o value "$discoduro_device")
backup_fstype=$(blkid -s TYPE -o value "$backup_device")
wdelements_fstype=$(blkid -s TYPE -o value "$wdelements_device")

# Definir las nuevas entradas para el archivo fstab
new_entries="UUID=$discoduro_uuid  /media/discoduro        $discoduro_fstype    defaults,nofail        0       0
UUID=$wdelements_uuid  /media/WDElements       $wdelements_fstype    defaults,nofail        0       0
UUID=$backup_uuid      /media/Backup           $backup_fstype    defaults,nofail        0       0"

# Añadir las nuevas entradas al archivo fstab si no existen ya
if ! grep -q "UUID=$discoduro_uuid" /etc/fstab; then
    echo "$new_entries" >> /etc/fstab
    log "Nuevas entradas añadidas al archivo /etc/fstab."
else
    log "Las entradas ya están presentes en el archivo /etc/fstab."
fi

# Probar las nuevas monturas
log "Probando las nuevas entradas en /etc/fstab..."
if mount -a; then
    log "Las particiones se montaron correctamente."
else
    log "Error: Hubo un problema al montar las particiones. Revirtiendo cambios."
    cp /etc/fstab.backup /etc/fstab
    exit 1
fi

log "Configuración del archivo /etc/fstab completada."