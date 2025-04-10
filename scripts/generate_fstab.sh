#!/bin/bash
################################################################################
# Script Name: generate_fstab.sh
# Description: Gestiona puntos de montaje en /etc/fstab basándose en un archivo
#              JSON de forma idempotente, segura y resiliente.
# Author: Juan José Hipólito (Revisado por AI)
# Version: 2.1.0
# Date: 2024-04-04
# License: GNU GPL v3
# Usage: sudo bash manage_fstab_mounts.sh [--dry-run]
# Dependencies: jq, util-linux (blkid, findmnt, mountpoint), coreutils
################################################################################

# --- Configuración Inicial ---
# Asumiendo que utils.sh exporta/define INSTALL_DIR y CONFIG_DIR
source "/opt/confiraspa/lib/utils.sh" || { echo "CRITICAL: Cannot source utils.sh" >&2; exit 1; }

# --- Variables Globales ---
readonly FSTAB_FILE="/etc/fstab"
readonly CONFIG_FILE="${CONFIG_DIR}/puntos_de_montaje.json"
readonly USER_CONFIG_FILE="${CONFIG_DIR}/arr_user.json" # Para UID/GID
readonly LOCK_FILE="/var/lock/confiraspa_fstab.lock"
# Etiqueta para identificar nuestras entradas en fstab
readonly FSTAB_COMMENT_TAG="# Managed by Confiraspa:configure_fstab.sh"

# --- Opciones de Script ---
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    log "WARN" "Ejecutando en modo DRY-RUN. No se realizarán cambios en ${FSTAB_FILE}."
fi

# --- Funciones Auxiliares ---

# Valida el archivo de configuración JSON
validate_config() {
    local config_file="$1"
    log "DEBUG" "Validando archivo de configuración: ${config_file}"

    if ! jq -e '.' "$config_file" > /dev/null 2>&1; then
        log "ERROR" "Archivo JSON inválido: ${config_file}"
        return 1
    fi

    if ! jq -e 'has("puntos_de_montaje") and (.puntos_de_montaje | type == "array")' "$config_file" > /dev/null 2>&1; then
        log "ERROR" "Formato JSON incorrecto: falta la clave 'puntos_de_montaje' como array."
        return 1
    fi

    # Validar cada entrada dentro del array
    local errors=0
    while IFS= read -r entry; do
        local label path
        label=$(jq -re '.label // empty' <<< "$entry")
        path=$(jq -re '.ruta // empty' <<< "$entry")

        if [[ -z "$label" ]]; then
            log "ERROR" "Entrada JSON inválida: falta 'label'. Contenido: $(jq -c . <<< "$entry")"
            ((errors++))
        fi
        if [[ -z "$path" ]]; then
            log "ERROR" "Entrada JSON inválida: falta 'ruta' para label '${label:-?}'."
            ((errors++))
        elif [[ ! "$path" =~ ^/ ]]; then
            log "ERROR" "Ruta de montaje no absoluta para label '${label}': '${path}'"
            ((errors++))
        fi
    done < <(jq -c '.puntos_de_montaje[]' "$config_file")

    [[ "$errors" -eq 0 ]] || return 1
    log "DEBUG" "Configuración JSON validada correctamente."
    return 0
}

# Carga UID y GID del usuario de arr_user.json
load_arr_user_ids() {
    local -n _uid_ref="$1" # Pasado por referencia de nombre
    local -n _gid_ref="$2"

    _uid_ref="1000" # Default a 1000 (usuario pi a menudo)
    _gid_ref="1000" # Default a 1000

    if [[ ! -f "$USER_CONFIG_FILE" ]]; then
        log "WARN" "Archivo ${USER_CONFIG_FILE} no encontrado. Usando UID=1000, GID=1000 para NTFS/VFAT."
        return 0
    fi

    local user group user_id group_id
    user=$(jq -re '.user // empty' "$USER_CONFIG_FILE")
    group=$(jq -re '.group // empty' "$USER_CONFIG_FILE")

    if [[ -z "$user" || -z "$group" ]]; then
         log "WARN" "Archivo ${USER_CONFIG_FILE} incompleto. Usando UID=1000, GID=1000."
         return 0
    fi

    user_id=$(id -u "$user" 2>/dev/null) || { log "WARN" "Usuario '$user' de ${USER_CONFIG_FILE} no encontrado. Usando UID=1000."; user_id="1000"; }
    group_id=$(getent group "$group" | cut -d: -f3 2>/dev/null) || { log "WARN" "Grupo '$group' de ${USER_CONFIG_FILE} no encontrado. Usando GID=1000."; group_id="1000"; }

    _uid_ref="$user_id"
    _gid_ref="$group_id"
    log "INFO" "Usando UID=${_uid_ref} (Usuario: ${user}), GID=${_gid_ref} (Grupo: ${group}) para opciones NTFS/VFAT."
}


# Obtiene UUID y FSTYPE de un dispositivo por su LABEL
get_device_info_by_label() {
    local label="$1"
    local -n _uuid_ref="$2"  # Pasado por referencia de nombre
    local -n _fstype_ref="$3"

    local device_path
    # blkid puede tardar, usar timeout bajo
    device_path=$(timeout 5 blkid -L "$label" 2>/dev/null) || {
        log "ERROR" "No se encontró dispositivo con LABEL='${label}' o blkid timeout."
        return 1
    }

    # Verificar si encontró múltiples (aunque blkid -L suele devolver solo 1)
    local device_count
    device_count=$(echo "$device_path" | wc -l)
    if [[ "$device_count" -ne 1 ]]; then
        log "ERROR" "Se encontraron ${device_count} dispositivos con LABEL='${label}'. Se esperaba 1."
        return 1
    fi

    # Quitar posibles espacios extra
    device_path=$(echo "$device_path" | xargs)

    log "DEBUG" "Dispositivo para LABEL='${label}' encontrado: ${device_path}"

    # Obtener UUID y TYPE del dispositivo encontrado
    _uuid_ref=$(blkid -s UUID -o value "$device_path" 2>/dev/null) || { log "ERROR" "No se pudo obtener UUID para '${label}' (${device_path})."; return 1; }
    _fstype_ref=$(blkid -s TYPE -o value "$device_path" 2>/dev/null) || { log "ERROR" "No se pudo obtener FSTYPE para '${label}' (${device_path})."; return 1; }

    if [[ -z "$_uuid_ref" || -z "$_fstype_ref" ]]; then
        log "ERROR" "UUID o FSTYPE vacíos para '${label}' (${device_path})."
        return 1
    fi

    log "DEBUG" "Info para '${label}': UUID=${_uuid_ref}, FSTYPE=${_fstype_ref}"
    return 0
}

# Genera las opciones de montaje adecuadas para fstab
generate_fstab_options() {
    local fstype="$1"
    local mount_uid="$2" # UID a usar para NTFS/VFAT
    local mount_gid="$3" # GID a usar para NTFS/VFAT
    local base_options="defaults,nofail"

    # Opciones específicas por sistema de archivos
    case "$fstype" in
        ntfs|ntfs-3g)
            # uid/gid: propietario de archivos
            # dmask=0022 -> directorios 755 (rwxr-xr-x)
            # fmask=0133 -> archivos 644 (rw-r--r--)
            # permissions -> permite usar uid/gid/mask
            # windows_names -> evita nombres de archivo inválidos en windows
            # locale=es_ES.UTF-8 -> (Opcional) para nombres con caracteres especiales
            echo "${base_options},uid=${mount_uid},gid=${mount_gid},dmask=0022,fmask=0133,permissions,windows_names"
            ;;
        vfat)
            # uid/gid: propietario
            # umask=0022 -> permisos 755 para dirs, 644 para archivos
            # flush -> escritura más frecuente (útil para pendrives, opcional)
            echo "${base_options},uid=${mount_uid},gid=${mount_gid},umask=0022"
            ;;
        ext4|xfs|btrfs)
            # Para sistemas de archivos Linux nativos, 'defaults' suele ser suficiente.
            # Podrías añadir 'noatime' para rendimiento si no necesitas el timestamp de acceso.
            echo "${base_options},noatime"
            ;;
        *)
            # Para otros tipos, empezar solo con defaults,nofail
            log "WARN" "Tipo de sistema de archivos '${fstype}' no reconocido explícitamente. Usando opciones base: ${base_options}"
            echo "${base_options}"
            ;;
    esac
}

# Crea el punto de montaje si no existe y ajusta permisos básicos
create_mountpoint_dir() {
    local path="$1"
    log "DEBUG" "Asegurando punto de montaje: ${path}"

    if [[ ! -d "$path" ]]; then
        log "INFO" "Creando directorio de punto de montaje: ${path}"
        # Usar sudo explícito aquí, aunque el script se ejecute como root,
        # es buena práctica para claridad y si se reutiliza fuera.
        if ! sudo mkdir -p "$path"; then
            log "ERROR" "Fallo al crear directorio: ${path}"
            return 1
        fi
    fi

    # Permisos básicos para que se pueda montar, el fstab controlará el resto.
    # Propietario root:root es estándar para puntos de montaje en /media o /mnt.
    if ! sudo chmod 755 "$path" || ! sudo chown root:root "$path"; then
        log "WARN" "No se pudieron establecer permisos/propietario base (755, root:root) en: ${path}"
        # No fallar aquí necesariamente, mount podría funcionar igual.
    fi
    return 0
}

# --- Ejecución Principal ---
main() {
    # --- Setup Inicial ---
    check_root
    setup_error_handling
    # setup_paths # Ya se llama desde utils.sh si se sourcea correctamente

    # Dependencias esenciales
    install_dependencies "jq" "util-linux" || exit 1 # blkid, findmnt, etc. están en util-linux

    log "INFO" "== Iniciando gestión de puntos de montaje de ${FSTAB_FILE} =="

    # Validar configuración JSON
    validate_config "$CONFIG_FILE" || { log "ERROR" "Archivo de configuración inválido."; exit 1; }

    # Cargar UID/GID para opciones de montaje
    local mount_uid mount_gid
    load_arr_user_ids mount_uid mount_gid

    # --- Bloqueo y Backup ---
    log "DEBUG" "Adquiriendo lock: ${LOCK_FILE}"
    # Usar descriptor de archivo 200 para evitar conflictos
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log "ERROR" "Otro proceso está modificando ${FSTAB_FILE} (lock activo en ${LOCK_FILE}). Saliendo."
        exit 1
    fi
    # Asegurar que el lock se libera al salir (normal, error, señal)
    trap 'flock -u 200; rm -f "$temp_fstab_file"; exit' EXIT HUP INT QUIT TERM

    # Crear backup usando la función de utils.sh
    if ! create_backup "$FSTAB_FILE"; then
        log "ERROR" "No se pudo crear backup de ${FSTAB_FILE}. Saliendo."
        exit 1 # Salir si no podemos crear backup
    fi

    # --- Procesamiento ---
    local temp_fstab_file changes_made=0 errors_occurred=0
    # Crear archivo temporal seguro
    temp_fstab_file=$(mktemp) || { log "ERROR" "No se pudo crear archivo temporal."; exit 1; }
    chmod 644 "$temp_fstab_file" # Permisos similares a fstab

    # Mapa para guardar las entradas deseadas (path -> linea_fstab_completa)
    declare -A desired_entries
    # Mapa para rastrear puntos de montaje gestionados por este script
    declare -A managed_paths

    log "INFO" "Procesando entradas desde ${CONFIG_FILE}..."
    while IFS= read -r entry; do
        local label path uuid fstype options fstab_line

        label=$(jq -re '.label' <<< "$entry")
        path=$(jq -re '.ruta' <<< "$entry")
        log "INFO" "Procesando definición para: LABEL=${label} -> ${path}"

        # Obtener info del dispositivo
        if ! get_device_info_by_label "$label" uuid fstype; then
            ((errors_occurred++))
            log "WARN" "Saltando entrada para LABEL=${label} debido a error anterior."
            continue # Saltar al siguiente item del JSON
        fi

        # Crear punto de montaje (directorio)
        if ! create_mountpoint_dir "$path"; then
            ((errors_occurred++))
            log "WARN" "Saltando entrada para LABEL=${label} debido a error al crear/configurar ${path}."
            continue
        fi

        # Generar opciones y línea fstab deseada
        options=$(generate_fstab_options "$fstype" "$mount_uid" "$mount_gid")
        # Construir la línea completa como debería estar en fstab
        fstab_line="UUID=${uuid} ${path} ${fstype} ${options} 0 0 ${FSTAB_COMMENT_TAG} (LABEL=${label})"

        # Guardar la línea deseada y marcar la ruta como gestionada
        desired_entries["$path"]="$fstab_line"
        managed_paths["$path"]=1
        log "DEBUG" "Entrada deseada para ${path}: ${fstab_line}"

    done < <(jq -c '.puntos_de_montaje[]' "$CONFIG_FILE")

    log "INFO" "Generando nuevo contenido de ${FSTAB_FILE}..."
    local current_fstab_content new_fstab_content="" line mount_point is_managed
    # Leer fstab actual línea por línea
    while IFS= read -r line || [[ -n "$line" ]]; do # Asegurar leer la última línea si no acaba en newline
        # Preservar comentarios y líneas vacías
        if [[ "$line" =~ ^\s*# ]] || [[ -z "$line" ]]; then
            new_fstab_content+="${line}"$'\n'
            continue
        fi

        # Intentar extraer el punto de montaje (segundo campo) de líneas válidas
        # Usar awk para manejar mejor espacios múltiples
        mount_point=$(echo "$line" | awk '{print $2}')

        # Si no se puede extraer mount_point o la línea no parece válida, preservarla por seguridad
        if [[ -z "$mount_point" || ! "$mount_point" =~ ^/ ]]; then
             log "WARN" "Línea fstab no reconocida, preservando: ${line}"
             new_fstab_content+="${line}"$'\n'
             continue
        fi

        # Comprobar si este mount_point está gestionado por nosotros
        is_managed=0
        if [[ -v managed_paths["$mount_point"] ]]; then
            is_managed=1
        fi

        if [[ "$is_managed" -eq 1 ]]; then
            # Es una ruta que gestionamos. Comprobar si la línea actual coincide con la deseada.
            local desired_line="${desired_entries[$mount_point]}"
            # Comparar ignorando el comentario autogenerado si ya existe uno similar
            local line_no_comment="${line%#*}" # Quitar comentario
            local desired_line_no_comment="${desired_line%#*}"
            line_no_comment="${line_no_comment%"${line_no_comment##*[![:space:]]}"}" # Trim trailing space
            desired_line_no_comment="${desired_line_no_comment%"${desired_line_no_comment##*[![:space:]]}"}" # Trim trailing space

            if [[ "$line_no_comment" == "$desired_line_no_comment" ]]; then
                log "DEBUG" "Entrada existente para ${mount_point} ya es correcta."
                new_fstab_content+="${line}"$'\n' # Preservar la línea exacta existente (incluido comentario si era el nuestro)
            else
                log "INFO" "Actualizando entrada existente para ${mount_point}."
                log "DEBUG" "  Vieja: ${line}"
                log "DEBUG" "  Nueva: ${desired_line}"
                new_fstab_content+="${desired_line}"$'\n' # Añadir la nueva línea corregida
                changes_made=1
            fi
            # Marcar como procesada eliminándola del mapa de deseadas
            unset desired_entries["$mount_point"]
        else
            # No es una ruta gestionada por nosotros, preservarla tal cual
            log "DEBUG" "Preservando entrada fstab no gestionada para: ${mount_point}"
            new_fstab_content+="${line}"$'\n'
        fi
    done < "$FSTAB_FILE"

    # Añadir entradas nuevas (las que quedaron en desired_entries)
    if [[ "${#desired_entries[@]}" -gt 0 ]]; then
        log "INFO" "Añadiendo nuevas entradas gestionadas a fstab:"
        for path in "${!desired_entries[@]}"; do
            log "INFO" "  + ${path}"
            new_fstab_content+="${desired_entries[$path]}"$'\n'
            changes_made=1
        done
    fi

    # --- Aplicar Cambios ---
    if [[ "$changes_made" -eq 1 ]]; then
        log "INFO" "Se detectaron cambios necesarios en ${FSTAB_FILE}."
        # Escribir el nuevo contenido al archivo temporal
        if ! printf '%s' "$new_fstab_content" > "$temp_fstab_file"; then
             log "ERROR" "Fallo al escribir al archivo temporal ${temp_fstab_file}. No se aplicarán cambios."
             ((errors_occurred++))
        else
            # Verificar sintaxis básica del archivo temporal antes de mover
            # mount -a --fake no siempre existe o funciona como se espera,
            # pero intentarlo es mejor que nada.
            log "DEBUG" "Verificando sintaxis del fstab temporal con 'mount -a -f -v'..."
            if sudo mount -a -f -v -O no_netdev --target "$temp_fstab_file" &> /dev/null; then
                log "DEBUG" "Sintaxis del fstab temporal parece correcta."

                if $DRY_RUN; then
                    log "WARN" "[DRY-RUN] Se habrían aplicado los siguientes cambios a ${FSTAB_FILE}:"
                    diff -u "$FSTAB_FILE" "$temp_fstab_file" || true # Mostrar diff
                else
                    log "INFO" "Aplicando cambios a ${FSTAB_FILE}..."
                    # Mover atómicamente (si está en el mismo sistema de archivos)
                    if ! sudo mv "$temp_fstab_file" "$FSTAB_FILE"; then
                        log "ERROR" "¡¡FALLO CRÍTICO al mover ${temp_fstab_file} a ${FSTAB_FILE}!!"
                        log "ERROR" "Intentando restaurar backup..."
                        # La función restore_backup ya existe en utils.sh
                        if restore_backup "$FSTAB_FILE"; then
                           log "INFO" "Backup de fstab restaurado."
                        else
                           log "ERROR" "¡FALLO AL RESTAURAR BACKUP DE FSTAB! Revisión manual requerida."
                        fi
                        ((errors_occurred++))
                        # El trap limpiará el temp file y liberará el lock
                        exit 1 # Salir con error
                    else
                        log "SUCCESS" "${FSTAB_FILE} actualizado correctamente."
                        # Intentar montar todo después de actualizar fstab
                        log "INFO" "Ejecutando 'sudo mount -a' para montar nuevos puntos..."
                        if ! sudo mount -a; then
                             log "WARN" "'mount -a' finalizó con errores. Revisar estado de montajes con 'mount' o 'findmnt'."
                             # No consideramos esto un error fatal del script en sí, pero sí una advertencia.
                        else
                             log "INFO" "'mount -a' completado."
                        fi
                    fi
                fi
            else
                log "ERROR" "¡La verificación de sintaxis del fstab temporal falló! No se aplicarán cambios."
                log "ERROR" "Contenido del fstab temporal inválido (guardado en ${temp_fstab_file} para depuración):"
                cat "$temp_fstab_file" # Mostrar contenido para ayudar a depurar
                ((errors_occurred++))
                # El archivo temporal se eliminará por el trap, pero el fstab original no se tocó.
            fi
        fi
    else
        log "INFO" "No se requieren cambios en ${FSTAB_FILE}."
        rm -f "$temp_fstab_file" # Limpiar archivo temporal si no hubo cambios
    fi

    # --- Limpieza y Salida ---
    # El trap se encargará de flock -u y rm -f temp_fstab_file

    if [[ "$errors_occurred" -gt 0 ]]; then
        log "ERROR" "El script finalizó con ${errors_occurred} error(es)."
        exit 1
    else
        log "SUCCESS" "Gestión de puntos de montaje completada exitosamente."
        exit 0
    fi
}

# --- Ejecutar Programa Principal ---
main "$@"