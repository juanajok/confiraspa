#!/bin/bash

################################################################################
# Script Name: manage_mounts.sh
# Description: Gestiona puntos de montaje basándose en un archivo JSON,
#              creando directorios de montaje, montando dispositivos y
#              actualizando /etc/fstab de forma idempotente.
# Author: Juan José Hipólito
# Version: 1.2.0
# Date: 2024-03-31
# License: GNU GPL v3
# Usage: Ejecutar con privilegios de superusuario (sudo).
# Dependencies: blkid, jq, mkdir, mount, grep, awk, sed, flock
#
# Formato JSON esperado en puntos_de_montaje.json:
# {
#   "puntos_de_montaje": [
#     {
#       "label": "DATOS",
#       "ruta": "/mnt/datos"
#     }
#   ]
# }
################################################################################


# Cargar utilidades después de definir INSTALL_DIR
source /opt/confiraspa/lib/utils.sh
echo "INSTALL_DIR: $INSTALL_DIR"
echo "LOG_DIR: $LOG_DIR"
echo "CONFIG_DIR: $CONFIG_DIR"

# --- Inicialización ---
check_root
setup_error_handling
setup_paths
install_dependencies "jq" "util-linux" "sed"

# --- Variables Globales ---
readonly FSTAB_FILE="/etc/fstab"
readonly CONFIG_FILE="$CONFIG_DIR/puntos_de_montaje.json"
readonly BACKUP_SUFFIX="$(date +%Y%m%d%H%M%S)"
DRY_RUN=false

# --- Funciones de Utilidad ---
validate_mount_path() {
    local path="$1"
    if [[ ! "$path" =~ ^/ ]]; then
        log "ERROR" "La ruta de montaje debe ser absoluta: $path"
        return 1
    fi
    return 0
}

backup_fstab() {
    local backup_file="${FSTAB_FILE}.bak_${BACKUP_SUFFIX}"
    if ! cp "$FSTAB_FILE" "$backup_file"; then
        log "ERROR" "No se pudo crear la copia de seguridad de $FSTAB_FILE"
        exit 1
    fi
    log "INFO" "Copia de seguridad creada: $backup_file"
}

# --- Verificaciones Iniciales ---
if [ ! -f "$CONFIG_FILE" ]; then
    log "ERROR" "Archivo de configuración '$CONFIG_FILE' no encontrado."
    exit 1
fi

# Validación mejorada del JSON
if ! jq -e 'has("puntos_de_montaje") and (.puntos_de_montaje | type == "array" and length > 0)' "$CONFIG_FILE" >/dev/null 2>&1; then
    log "ERROR" "El archivo JSON '$CONFIG_FILE' no tiene el formato correcto o está vacío."
    exit 1
fi

# Crear copia de seguridad de fstab
backup_fstab

# --- Procesamiento Principal ---
while read -r mount_point; do
    # Obtener y validar datos
    label=$(echo "$mount_point" | jq -r '.label')
    mount_path=$(echo "$mount_point" | jq -r '.ruta')

    if [ -z "$label" ] || [ -z "$mount_path" ]; then
        log "ERROR" "Falta 'label' o 'ruta' en la configuración JSON para una entrada."
        continue
    fi

    if ! validate_mount_path "$mount_path"; then
        continue
    fi

    log "INFO" "Procesando dispositivo con label '$label' y ruta de montaje '$mount_path'..."

    # Crear punto de montaje con manejo de errores mejorado
    if [ ! -d "$mount_path" ]; then
        if ! mkdir -p "$mount_path"; then
            log "ERROR" "No se pudo crear el directorio de montaje: $mount_path"
            continue
        fi
        log "INFO" "Directorio de montaje creado: $mount_path"
    fi

    # Verificar permisos con mensajes detallados
    current_perms=$(stat -c '%a' "$mount_path")
    current_owner=$(stat -c '%U:%G' "$mount_path")
    if [ "$current_perms" != "755" ] || [ "$current_owner" != "root:root" ]; then
        chmod 755 "$mount_path" || {
            log "ERROR" "No se pudieron establecer los permisos en $mount_path"
            continue
        }
        chown root:root "$mount_path" || {
            log "ERROR" "No se pudo cambiar el propietario de $mount_path"
            continue
        }
        log "INFO" "Permisos actualizados: $current_perms -> 755, $current_owner -> root:root"
    fi

    # Obtener dispositivo con manejo mejorado de errores
    readarray -t devices < <(blkid -L "$label" 2>/dev/null || true)
    if [ "${#devices[@]}" -gt 1 ]; then
        log "ERROR" "Múltiples dispositivos encontrados con label '$label': ${devices[*]}"
        continue
    elif [ "${#devices[@]}" -eq 0 ]; then
        log "ERROR" "No se encontró dispositivo con label '$label'"
        continue
    fi
    device="${devices[0]}"

    # Obtener UUID y tipo de sistema de archivos con validación
    uuid=$(blkid -s UUID -o value "$device") || {
        log "ERROR" "No se pudo obtener UUID para $device"
        continue
    }
    fstype=$(blkid -s TYPE -o value "$device") || {
        log "ERROR" "No se pudo obtener tipo de sistema de archivos para $device"
        continue
    }

    # Configurar opciones de montaje según el sistema de archivos
    mount_options="defaults,nofail"
    case "$fstype" in
        ntfs|ntfs-3g)
            mount_options="$mount_options,uid=1000,gid=1000,dmask=022,fmask=133"
            ;;
        vfat)
            mount_options="$mount_options,uid=1000,gid=1000,umask=022"
            ;;
    esac

    # Actualizar fstab con manejo de errores mejorado
    existing_entry=$(grep -E "^[^#]*[[:space:]]+$mount_path[[:space:]]" "$FSTAB_FILE" || true)
    if [ -n "$existing_entry" ]; then
        if echo "$existing_entry" | grep -q "UUID=$uuid"; then
            log "INFO" "La entrada para $mount_path ya existe con UUID correcto"
        else
            if ! sed -i.bak "/^[^#]*[[:space:]]\+$mount_path[[:space:]]/c\UUID=$uuid $mount_path $fstype $mount_options 0 0" "$FSTAB_FILE"; then
                log "ERROR" "Error al actualizar entrada en $FSTAB_FILE"
                continue
            fi
            log "INFO" "Entrada actualizada en $FSTAB_FILE para $mount_path"
        fi
    else
        if ! echo "UUID=$uuid $mount_path $fstype $mount_options 0 0" >> "$FSTAB_FILE"; then
            log "ERROR" "Error al añadir entrada en $FSTAB_FILE"
            continue
        fi
        log "INFO" "Nueva entrada añadida a $FSTAB_FILE para $mount_path"
    fi

    # Montar dispositivo con mejor manejo de errores
    if mountpoint -q "$mount_path"; then
        log "INFO" "Dispositivo ya montado en $mount_path"
    else
        if ! mount "$mount_path" 2>/dev/null; then
            log "ERROR" "Error al montar $mount_path: $(mount "$mount_path" 2>&1)"
            continue
        fi
        log "INFO" "Dispositivo montado exitosamente en $mount_path"
    fi

done < <(jq -c '.puntos_de_montaje[]' "$CONFIG_FILE")

log "INFO" "Proceso completado exitosamente"