#!/bin/bash

# Script: setup_logrotate_from_json.sh
# Descripción: Configura logrotate para rotar los logs de jobs de backup especificados en un archivo JSON.
# Autor: [Tu Nombre]
# Fecha de creación: [Fecha de creación]
# Última modificación: [Fecha actual]

# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log_file="/var/log/setup_logrotate_from_json.log"

log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$log_file"
}

# Limpiar archivos temporales al salir
cleanup() {
    rm -f /tmp/error_logrotate.txt
}
trap cleanup EXIT

# Comprobación de dependencias
command -v jq >/dev/null 2>&1 || { log "ERROR" "El comando 'jq' no está instalado. Por favor, instálalo e intenta de nuevo."; exit 1; }
command -v logrotate >/dev/null 2>&1 || { log "ERROR" "El comando 'logrotate' no está instalado. Por favor, instálalo e intenta de nuevo."; exit 1; }

# Verificar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    log "ERROR" "Este script debe ser ejecutado con privilegios de superusuario (sudo)."
    exit 1
fi

# Obtener la ruta del script de manera portátil
script_dir="$(cd "$(dirname "$0")" && pwd)"

# Permitir que el archivo JSON sea pasado como argumento
json_file="${1:-$script_dir/configs/logrotate_jobs_config.json}"

# Verifica si el archivo JSON existe
if [ ! -f "$json_file" ]; then
    log "ERROR" "El archivo de configuración $json_file no se encuentra."
    exit 1
fi

# Validar el formato del archivo JSON
if ! jq empty "$json_file" >/dev/null 2>&1; then
    log "ERROR" "El archivo JSON '$json_file' no tiene un formato válido."
    exit 1
fi

log "INFO" "Configurando logrotate desde $json_file..."

# Leer las configuraciones del archivo JSON
jq -c '.jobs[]' "$json_file" | while read -r config; do
    name=$(echo "$config" | jq -r '.name // empty')
    path=$(echo "$config" | jq -r '.path // empty')
    rotate=$(echo "$config" | jq -r '.rotate // empty')
    frequency=$(echo "$config" | jq -r '.frequency // empty')
    compress=$(echo "$config" | jq -r '.compress // empty')
    missingok=$(echo "$config" | jq -r '.missingok // empty')
    notifempty=$(echo "$config" | jq -r '.notifempty // empty')
    create=$(echo "$config" | jq -r '.create // empty')
    postrotate=$(echo "$config" | jq -r '.postrotate // empty')

    # Validar campos obligatorios
    if [ -z "$name" ] || [ -z "$path" ] || [ -z "$rotate" ]; then
        log "ERROR" "La configuración para '$name' está incompleta. Campos obligatorios: name, path, rotate."
        continue
    fi

    # Ruta del archivo de configuración de logrotate
    config_file="/etc/logrotate.d/$name"

    # Generar el contenido deseado de la configuración
    desired_config=$(mktemp)
    {
        echo "$path {"
        echo "    rotate $rotate"
        case "$frequency" in
            daily) echo "    daily" ;;
            weekly) echo "    weekly" ;;
            monthly) echo "    monthly" ;;
            yearly) echo "    yearly" ;;
            *) ;;
        esac
        [ "$compress" == "true" ] && echo "    compress"
        [ "$missingok" == "true" ] && echo "    missingok"
        [ "$notifempty" == "true" ] && echo "    notifempty"
        [ -n "$create" ] && echo "    create $create"
        if [ -n "$postrotate" ]; then
            echo "    postrotate"
            echo "        $(echo -e "$postrotate" | sed 's/^/        /')"
            echo "    endscript"
        fi
        echo "}"
    } > "$desired_config"

    # Si el archivo de configuración existe y es igual al deseado, no hacer nada
    if [ -f "$config_file" ]; then
        if cmp -s "$desired_config" "$config_file"; then
            log "INFO" "La configuración para '$name' ya está actualizada. No se requieren cambios."
            rm "$desired_config"
            continue
        else
            # Crear copia de seguridad con timestamp
            timestamp=$(date '+%Y%m%d%H%M%S')
            cp "$config_file" "${config_file}.bak.$timestamp"
            log "INFO" "Se ha creado una copia de seguridad de $config_file en ${config_file}.bak.$timestamp."
        fi
    fi

    # Mover el archivo deseado al archivo de configuración
    mv "$desired_config" "$config_file"

    # Establecer permisos y propietario adecuados
    chown root:root "$config_file"
    chmod 644 "$config_file"

    log "INFO" "Configuración de logrotate actualizada para '$name' en $config_file."

    # Validar la sintaxis del archivo de configuración
    if logrotate -d "$config_file" >/dev/null 2>/tmp/error_logrotate.txt; then
        log "INFO" "La configuración de logrotate para '$name' es válida."
    else
        log "ERROR" "La configuración de logrotate para '$name' contiene errores:"
        cat /tmp/error_logrotate.txt | tee -a "$log_file"

        # Restaurar la copia de seguridad si existe
        if ls "${config_file}.bak."* 1>/dev/null 2>&1; then
            latest_backup=$(ls -t "${config_file}.bak."* | head -n1)
            mv "$latest_backup" "$config_file"
            log "INFO" "Se ha restaurado la configuración anterior para '$name' desde $latest_backup."
        else
            rm "$config_file"
            log "INFO" "Se ha eliminado la configuración inválida para '$name'."
        fi
    fi

done

log "INFO" "Configuración de logrotate completada."
