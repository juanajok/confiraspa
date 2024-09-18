#!/bin/bash
set -e

# Script: setup_logrotate_from_json.sh
# Descripción: Configura logrotate para rotar los logs de jobs de backup especificados en un archivo JSON.
# Autor: [Tu Nombre]
# Fecha de creación: [Fecha]

# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

# Verificar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    log "ERROR" "Este script debe ser ejecutado con privilegios de superusuario (sudo)."
    exit 1
fi

# Ruta del script y del archivo JSON
script_dir="$(dirname "$(realpath "$0")")"
json_file="$script_dir/configs/logrotate_jobs_config.json"

# Verifica si el archivo JSON existe
if [ ! -f "$json_file" ]; then
    log "ERROR" "El archivo de configuración $json_file no se encuentra."
    exit 1
fi

log "INFO" "Configurando logrotate desde $json_file..."

# Lee las configuraciones del archivo JSON
jq -c '.jobs[]' "$json_file" | while read -r config; do
    name=$(echo "$config" | jq -r '.name')
    path=$(echo "$config" | jq -r '.path')
    rotate=$(echo "$config" | jq -r '.rotate')
    daily=$(echo "$config" | jq -r '.daily')
    compress=$(echo "$config" | jq -r '.compress')
    missingok=$(echo "$config" | jq -r '.missingok')
    notifempty=$(echo "$config" | jq -r '.notifempty')
    create=$(echo "$config" | jq -r '.create')
    postrotate=$(echo "$config" | jq -r '.postrotate')

    # Validar campos obligatorios
    if [ -z "$name" ] || [ -z "$path" ] || [ -z "$rotate" ]; then
        log "ERROR" "La configuración para '$name' está incompleta. Campos obligatorios: name, path, rotate."
        continue
    fi

    # Ruta del archivo de configuración de logrotate
    config_file="/etc/logrotate.d/$name"

    # Hacer copia de seguridad si el archivo ya existe
    if [ -f "$config_file" ]; then
        cp "$config_file" "${config_file}.bak"
        log "INFO" "Se ha creado una copia de seguridad de $config_file en ${config_file}.bak."
    fi

    # Crear el archivo de configuración de logrotate
    {
        echo "$path {"
        echo "    rotate $rotate"
        [ "$daily" == "true" ] && echo "    daily"
        [ "$compress" == "true" ] && echo "    compress"
        [ "$missingok" == "true" ] && echo "    missingok"
        [ "$notifempty" == "true" ] && echo "    notifempty"
        [ -n "$create" ] && echo "    create $create"
        if [ -n "$postrotate" ]; then
            echo "    postrotate"
            echo "        $postrotate"
            echo "    endscript"
        fi
        echo "}"
    } > "$config_file"

    log "INFO" "Configuración de logrotate creada para '$name' en $config_file."

    # Validar la sintaxis del archivo de configuración
    if logrotate -d "$config_file" > /dev/null 2>&1; then
        log "INFO" "La configuración de logrotate para '$name' es válida."
    else
        log "ERROR" "La configuración de logrotate para '$name' contiene errores."
        # Restaurar la copia de seguridad si existe
        if [ -f "${config_file}.bak" ]; then
            mv "${config_file}.bak" "$config_file"
            log "INFO" "Se ha restaurado la configuración anterior para '$name'."
        else
            rm "$config_file"
            log "INFO" "Se ha eliminado la configuración inválida para '$name'."
        fi
    fi
done

log "INFO" "Configuración de logrotate completada."
