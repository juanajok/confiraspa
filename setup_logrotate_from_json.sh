#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Verifica si el archivo logrotate_config.json existe
if [ ! -f logrotate_config.json ]; then
    log "Error: El archivo logrotate_config.json no se encuentra."
    exit 1
fi

# Imprime un mensaje indicando que se está configurando logrotate
log "Configurando logrotate desde JSON..."

# Lee las configuraciones del archivo JSON
configurations=$(jq -c '.[]' logrotate_config.json)

# Itera sobre cada configuración
echo "$configurations" | while IFS= read -r config; do
    path=$(echo "$config" | jq -r '.path')
    options=$(echo "$config" | jq -r '.options')

    # Crea un archivo de configuración de logrotate
    config_file="/etc/logrotate.d/$(basename "$path")"
    echo "$path $options" > "$config_file"
    log "Configuración de logrotate creada para $path."
done

log "Configuración de logrotate completada."
