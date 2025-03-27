#!/bin/bash

################################################################################
# Script Name: manage_mounts.sh
# Description: Gestiona puntos de montaje basándose en un archivo JSON,
#              creando directorios de montaje, montando dispositivos y
#              actualizando /etc/fstab de forma idempotente.
# Author: Juan José Hipólito
# Version: 1.1.0
# Date: 2024-11-07
# License: GNU GPL v3
# Usage: Ejecutar con privilegios de superusuario (sudo).
# Dependencies: blkid, jq, mkdir, mount, grep, awk, sed, flock
################################################################################

source /opt/confiraspa/lib/utils.sh

check_root
setup_error_handling
setup_paths
install_dependencies "jq"  # dependencias


# Configuración
CONFIG_FILE="$CONFIG_DIR/puntos_de_montaje.json"
FSTAB_FILE="/etc/fstab"

# Implementar bloqueo para evitar ejecuciones concurrentes
exec 200>/var/lock/manage_mounts.lock
flock -n 200 || { echo "Otra instancia del script está en ejecución."; exit 1; }


log "INFO" "Iniciando el script..."

# Verificar la existencia del archivo de configuración
if [ ! -f "$CONFIG_FILE" ]; then
    log "ERROR" "Archivo de configuración '$CONFIG_FILE' no encontrado."
    exit 1
fi

# Verificar la sintaxis y estructura del archivo JSON
if ! jq -e '.puntos_de_montaje and (.puntos_de_montaje | type == "array")' "$CONFIG_FILE" >/dev/null 2>&1; then
    log "ERROR" "El archivo JSON '$CONFIG_FILE' no contiene un arreglo 'puntos_de_montaje' válido."
    exit 1
fi

# Crear copia de seguridad de /etc/fstab
cp "$FSTAB_FILE" "${FSTAB_FILE}.bak_$(date +%Y%m%d%H%M%S)"
log "INFO" "Copia de seguridad de $FSTAB_FILE creada."

# Procesar cada punto de montaje
while read -r mount_point; do
    # Obtener label y ruta
    label=$(echo "$mount_point" | jq -r '.label')
    mount_path=$(echo "$mount_point" | jq -r '.ruta')

    # Verificar que label y mount_path no estén vacíos
    if [ -z "$label" ] || [ -z "$mount_path" ]; then
        log "Falta 'label' o 'ruta' en la configuración JSON para una entrada."
        exit 1
    fi

    log "INFO" "Procesando dispositivo con label '$label' y ruta de montaje '$mount_path'..."

    # Crear el punto de montaje si no existe
    if [ ! -d "$mount_path" ]; then
        mkdir -p "$mount_path"
        log "INFO" "Directorio de montaje creado: $mount_path."
    fi

    # Verificar y corregir permisos y propietarios
    if [ "$(stat -c '%a' "$mount_path")" != "755" ] || [ "$(stat -c '%U:%G' "$mount_path")" != "root:root" ]; then
        chmod 755 "$mount_path"
        chown root:root "$mount_path"
        log "INFO" "Permisos y propietarios actualizados para $mount_path."
    else
        log "INFO" "Permisos y propietarios correctos en $mount_path."
    fi

    # Obtener el dispositivo asociado a la etiqueta
    devices=( $(blkid -L "$label" 2>/dev/null) )
    if [ "${#devices[@]}" -gt 1 ]; then
        log "ERROR" "Se encontraron múltiples dispositivos con la etiqueta '$label'. Por favor, asegúrate de que las etiquetas sean únicas."
        continue
    elif [ "${#devices[@]}" -eq 0 ]; then
        log "ERROR" "No se encontró un dispositivo con la etiqueta '$label'."
        continue
    else
        device="${devices[0]}"
    fi

    # Obtener UUID y tipo de sistema de archivos
    uuid=$(blkid -s UUID -o value "$device")
    fstype=$(blkid -s TYPE -o value "$device")

    # Verificar que se obtuvieron UUID y fstype
    if [ -z "$uuid" ] || [ -z "$fstype" ]; then
        log "ERROR" "No se pudo obtener UUID o tipo de sistema de archivos para el dispositivo '$device'."
        continue
    fi

    # Opciones de montaje
    mount_options="defaults,nofail"

    # Añadir opciones específicas según el tipo de sistema de archivos
    case "$fstype" in
        ntfs|ntfs-3g)
            mount_options="$mount_options,uid=1000,gid=1000,dmask=022,fmask=133"
            ;;
        vfat)
            mount_options="$mount_options,uid=1000,gid=1000,umask=022"
            ;;
    esac

    # Verificar si la entrada ya existe en /etc/fstab
    existing_entry=$(grep -E "^[^#]*[[:space:]]+$mount_path[[:space:]]" "$FSTAB_FILE" || true)
    if [ -n "$existing_entry" ]; then
        if echo "$existing_entry" | grep -q "UUID=$uuid"; then
            log "ERROR" "La entrada para $mount_path ya existe en $FSTAB_FILE con UUID correcto."
        else
            # Actualizar la entrada existente
            sed -i.bak "/^[^#]*[[:space:]]\+$mount_path[[:space:]]/c\UUID=$uuid $mount_path $fstype $mount_options 0 0" "$FSTAB_FILE"
            log "INFO" "Entrada actualizada en $FSTAB_FILE para $mount_path."
        fi
    else
        # Añadir nueva entrada
        echo "UUID=$uuid $mount_path $fstype $mount_options 0 0" >> "$FSTAB_FILE"
        log "INFO" "Entrada añadida a $FSTAB_FILE para $mount_path."
    fi

    # Verificar si el dispositivo ya está montado
    if mountpoint -q "$mount_path"; then
        log "INFO" "El dispositivo ya está montado en $mount_path."
    else
        # Intentar montar el dispositivo
        if mount "$mount_path"; then
            log "INFO" "Dispositivo montado en $mount_path exitosamente."
        else
            log ""ERROR" Error al montar $mount_path."
            continue
        fi
    fi
done < <(jq -c '.puntos_de_montaje[]' "$CONFIG_FILE")

log "INFO" "Proceso completado."
