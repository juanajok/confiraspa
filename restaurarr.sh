#!/bin/bash

# Función para imprimir mensajes con información de la función que los llama y la fecha y hora
function log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${FUNCNAME[1]}: $1"
}

# Función para restaurar una aplicación
function restore_app() {
    local app_name=$1
    local backup_dir=$2
    local backup_ext=$3
    local restore_dir=$4

    log "Iniciando restauración de la aplicación $app_name"

    # Verificar si la ruta de backup existe y contiene archivos
    if [ ! -d "$backup_dir" ] || [ ! "$(ls -A $backup_dir)" ]; then
        log "La ruta de backup para $app_name no existe o no contiene archivos."
        return 1
    fi

    # Obtener el archivo más reciente en la ruta de backup
    local backup_file=$(ls -t "$backup_dir"/*"$backup_ext" | head -1)

    # Verificar si el archivo de backup existe
    if [ ! -f "$backup_file" ]; then
        log "El archivo de backup para $app_name no existe."
        return 1
    fi

    log "Restaurando $app_name desde $backup_file"

    # Detener el servicio
    systemctl stop "$app_name".service

    # Hacer una copia de seguridad de los archivos originales
    local app_dir=$(jq -r --arg app_name "$app_name" '.[$app_name].app_dir' restore_apps.json)
    cp "$app_dir"/"$app_name".db "$app_dir"/"$app_name".db.bak
    cp "$app_dir"/config.xml "$app_dir"/config.xml.bak

    log "Creada copia de seguridad de los archivos originales"

    # Descomprimir el backup en el directorio temporal
    local tmp_dir="$restore_dir/$app_name"
    mkdir -p "$tmp_dir"
    unzip "$backup_file" -d "$tmp_dir"

    log "Backup descomprimido en $tmp_dir"

    # Copiar los archivos del backup a la ubicación original
    cp "$tmp_dir"/"$app_name".db "$app_dir"/"$app_name".db
    cp "$tmp_dir"/config.xml "$app_dir"/config.xml

    log "Archivos del backup copiados a $app_dir"

    # Asignar los permisos adecuados a los archivos
    local sudo_user=$(whoami)
    local sudo_user_group=$(id -gn $sudo_user)
    chown -R "$sudo_user":"$sudo_user_group" "$app_dir"/"$app_name"
    chmod 755 "$app_dir"/"$app_name".db
    chmod 644 "$app_dir"/config.xml

    log "Permisos actualizados"

    # Iniciar el servicio
    systemctl start "$app_name".service

    log "$app_name restaurado exitosamente"
}

# Función principal
function main() {
    log "Comenzando la restauración de las aplicaciones."


    # Verificar si el archivo restore_apps.json existe
    if [ ! -f "restore_apps.json" ]; then
        log "El archivo restore_apps.json no existe. La restauración no puede continuar."
        return 1
    fi

    # Configuración de las aplicaciones a restaurar
    log "Leyendo la configuración de las aplicaciones a restaurar."
    apps=($(jq -r '.apps[].name' restore_apps.json))


    for app_name in "${apps[@]}"
    do
        backup_dir=$(jq -r --arg app_name "$app_name" '.[$app_name].backup_dir' restore_apps.json)
        backup_ext=$(jq -r --arg app_name "$app_name" '.[$app_name].backup_ext' restore_apps.json)
        restore_dir=$(jq -r --arg app_name "$app_name" '.[$app_name].restore_dir' restore_apps.json)

        log "Restaurando la aplicación $app_name."
        restore_app "$app_name" "$backup_dir" "$backup_ext" "$restore_dir"
    done

    log "Restauración de aplicaciones finalizada."
}
main    
