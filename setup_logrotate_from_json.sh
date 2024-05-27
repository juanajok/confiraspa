#!/bin/bash

# Script: setup_logrotate_from_json
# Descripción: Configura logrotate para rotar los logs de jobs de backup especificados en un archivo JSON.
# Autor: Tu nombre
# Fecha de creación: 26/05/2024

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Cambia el directorio de trabajo al directorio del script
cd "$(dirname "$0")"

# Verifica si el archivo logrotate_jobs_config.json existe
if [ ! -f logrotate_jobs_config.json ]; then
    log "Error: El archivo logrotate_jobs_config.json no se encuentra."
    exit 1
fi

# Imprime un mensaje indicando que se está configurando logrotate
log "Configurando logrotate desde JSON..."

# Lee las configuraciones del archivo JSON
configurations=$(jq -c '.jobs[]' logrotate_jobs_config.json)

# Itera sobre cada configuración
echo "$configurations" | while IFS= read -r config; do
    name=$(echo "$config" | jq -r '.name')
    path=$(echo "$config" | jq -r '.path')
    rotate=$(echo "$config" | jq -r '.rotate')
    daily=$(echo "$config" | jq -r '.daily')
    compress=$(echo "$config" | jq -r '.compress')
    missingok=$(echo "$config" | jq -r '.missingok')
    notifempty=$(echo "$config" | jq -r '.notifempty')
    create=$(echo "$config" | jq -r '.create')
    postrotate=$(echo "$config" | jq -r '.postrotate')

    # Crea un archivo de configuración de logrotate
    config_file="/etc/logrotate.d/$name"
    {
        echo "$path {"
        echo "    rotate $rotate"
        [ "$daily" == "true" ] && echo "    daily"
        [ "$compress" == "true" ] && echo "    compress"
        [ "$missingok" == "true" ] && echo "    missingok"
        [ "$notifempty" == "true" ] && echo "    notifempty"
        echo "    create $create"
        echo "    postrotate"
        echo "        $postrotate"
        echo "    endscript"
        echo "}"
    } > "$config_file"
    log "Configuración de logrotate creada para $name en $config_file."
done

log "Configuración de logrotate completada."

# Verificación de idempotencia
logrotate -d /etc/logrotate.conf
