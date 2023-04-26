#!/bin/bash

# Ruta del directorio de aplicaciones
app_dir="/var/lib"

# Función para imprimir mensajes con información de la función que los llama y la fecha y hora
function log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${FUNCNAME[1]}: $1"
}

# Función para restaurar una aplicación
function restore_app() {
    local app_name=$1
    local backup_dir="/media/Backup/${app_name}/scheduled"
    local backup_file=$(ls -t ${backup_dir}/*.zip | head -1)
    local tmp_dir="/tmp/${app_name}_restore"

    log "Restaurando ${app_name} desde ${backup_file}"

    # Detener el servicio
    systemctl stop ${app_name}.service

    # Hacer una copia de seguridad de los archivos originales
    cp ${app_dir}/${app_name}.db ${app_dir}/${app_name}.db.bak
    cp ${app_dir}/config.xml ${app_dir}/config.xml.bak

    # Descomprimir el backup en el directorio temporal
    mkdir -p ${tmp_dir}
    unzip ${backup_file} -d ${tmp_dir}

    # Copiar los archivos del backup a la ubicación original
    cp ${tmp_dir}/${app_name}.db ${app_dir}/${app_name}.db
    cp ${tmp_dir}/config.xml ${app_dir}/config.xml

    # Asignar los permisos adecuados a los archivos
    SUDO_USER_GROUP=$(id -gn $SUDO_USER)
    chown -R ${SUDO_USER}:${SUDO_USER_GROUP} ${app_dir}/${app_name}
    chmod 755 ${app_dir}/${app_name}.db
    chmod 644 ${app_dir}/config.xml

    # Iniciar el servicio
    systemctl start ${app_name}.service

    log "${app_name} restaurado exitosamente"
}

# Función principal
function main() {
    # Configuración de las aplicaciones a restaurar
    apps=($(jq -r '.[] | .name' apps.json))

    for app_name in "${apps[@]}"
    do
        restore_app "${app_name}"
    done
}

main "$@"

