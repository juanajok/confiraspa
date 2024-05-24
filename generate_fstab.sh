#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Imprime un mensaje indicando que se está iniciando la generación del archivo /etc/fstab
log "Iniciando la generación del archivo /etc/fstab..."

# Lista las particiones del sistema y las ordena por tamaño
particiones=$(lsblk -ln -o NAME,SIZE,TYPE,FSTYPE | grep -w 'part' | grep '^sd')
sorted_partitions=$(echo "$particiones" | sort -k2 -h)

# Asigna variables para cada partición
discoduro_part=$(echo "$sorted_partitions" | head -n 1 | awk '{print $1}')
discoduro_fstype=$(echo "$sorted_partitions" | head -n 1 | awk '{print $4}')
backup_part=$(echo "$sorted_partitions" | tail -n 2 | head -n 1 | awk '{print $1}')
backup_fstype=$(echo "$sorted_partitions" | tail -n 2 | head -n 1 | awk '{print $4}')
wdelements_part=$(echo "$sorted_partitions" | tail -n 1 | awk '{print $1}')
wdelements_fstype=$(echo "$sorted_partitions" | tail -n 1 | awk '{print $4}')

# Imprime las particiones identificadas
log "discoduro_part: $discoduro_part"
log "discoduro_fstype: $discoduro_fstype"
log "backup_part: $backup_part"
log "backup_fstype: $backup_fstype"
log "wdelements_part: $wdelements_part"
log "wdelements_fstype: $wdelements_fstype"

# Crea una copia de seguridad del archivo fstab si no existe
if [ ! -f /etc/fstab.backup ]; then
    cp /etc/fstab /etc/fstab.backup
    log "Copia de seguridad del archivo /etc/fstab creada."
else
    log "La copia de seguridad del archivo /etc/fstab ya existe."
fi

# Define las nuevas entradas para el archivo fstab
new_entries="/dev/$discoduro_part  /media/discoduro        $discoduro_fstype    defaults        0       0
/dev/$wdelements_part  /media/WDElements       $wdelements_fstype    defaults        0       0
/dev/$backup_part      /media/Backup           $backup_fstype    defaults        0       0"

# Añade las nuevas entradas al archivo fstab si no existen ya
if ! grep -q "/media/discoduro" /etc/fstab; then
    echo "$new_entries" >> /etc/fstab
    log "Nuevas entradas añadidas al archivo /etc/fstab."
else
    log "Las entradas ya están presentes en el archivo /etc/fstab."
fi

log "Finalizando la generación del archivo /etc/fstab..."
