#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message"
}

# Función para configurar comandos de crontab
configure_crontab() {
    log "Configurando comandos de crontab..."

    # Directorio del script
    script_path="$(dirname "$(realpath "$0")")"
    log "Directorio del script: $script_path"

    # Volvemos al directorio donde está el script
    cd "$script_path" || exit
    log "Cambiando al directorio del script..."

    # Reemplaza el marcador de posición por el valor de la variable $script_path
    json_data=$(sed "s@SCRIPT_PATH_PLACEHOLDER@$script_path@g" scripts_and_crontab.json)

    # Itera sobre el array de objetos JSON y ejecuta el cuerpo del bucle para cada objeto
    echo "$json_data" | jq -c '.[]' | while read -r entry; do
        script=$(echo "$entry" | jq -r '.script')
        crontab_entry=$(echo "$entry" | jq -r '.crontab_entry')

        # Aplicar permisos ejecutables
        log "Aplicando permisos ejecutables a $script..."
        chmod +x "$script"

        # Comprobar si el script ya está en el crontab de root
        if sudo crontab -l | grep -q "$script"; then
            log "El script $script ya está en el crontab de root."
        else
            # Agregar el script al crontab de root
            log "Agregando el script $script al crontab de root..."
            (sudo crontab -l 2>/dev/null; echo "$crontab_entry $script") | sudo crontab -
        fi
    done

    log "Configuración de comandos de crontab completada."
}

# Llamada a la función para configurar crontab
configure_crontab
