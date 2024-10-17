#!/bin/bash

# Script Name: install_amule.sh
# Description: Instala y configura aMule y sus servicios en una Raspberry Pi con Raspbian OS.
# Author: [Tu Nombre]
# Version: 1.2.1
# Date: [Fecha]
# License: MIT License

set -euo pipefail

#######################################
# Variables Globales
#######################################

usuario="amule"  # Cambia esto si usas otro usuario
user_home="/home/$usuario"
script_path="/opt/confiraspa"
creds_json="$script_path/configs/credenciales.json"
dirs_json="$script_path/configs/amule_directories.json"

#######################################
# Función para registrar mensajes con marca de tiempo y nivel de log
# Argumentos:
#   $1 - Nivel de log (INFO, ERROR, etc.)
#   $2 - Mensaje
#######################################
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

#######################################
# Función para verificar si se está ejecutando como root
#######################################
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log "ERROR" "Este script debe ser ejecutado como root. Usa sudo."
        exit 1
    fi
}

#######################################
# Función para verificar conectividad a Internet
#######################################
check_internet() {
    log "INFO" "Verificando conectividad a Internet..."
    if curl -s --head http://www.google.com/ | grep "200 OK" > /dev/null; then
        log "INFO" "Conectividad a Internet verificada."
    else
        log "ERROR" "No hay conexión a Internet. Verifica tu conexión y vuelve a intentarlo."
        exit 1
    fi
}

#######################################
# Función para instalar un paquete si no está instalado
# Argumentos:
#   $1 - Nombre del paquete
#######################################
install_package_if_needed() {
    local package="$1"
    if ! dpkg -l | grep -qw "$package"; then
        log "INFO" "Instalando paquete '$package'..."
        if apt-get install -y "$package"; then
            log "INFO" "Paquete '$package' instalado correctamente."
        else
            log "ERROR" "Fallo en la instalación del paquete '$package'. Verifica tu conexión a Internet o las fuentes de paquetes."
            exit 1
        fi
    else
        log "INFO" "El paquete '$package' ya está instalado."
    fi
}

#######################################
# Función para instalar dependencias y aMule
#######################################
install_amule() {
    log "INFO" "Instalando aMule y sus dependencias..."

    # Actualizar lista de paquetes
    if apt-get update; then
        log "INFO" "Lista de paquetes actualizada correctamente."
    else
        log "ERROR" "Fallo al actualizar la lista de paquetes. Verifica tu conexión a Internet."
        exit 1
    fi

    # Instalar paquetes necesarios
    install_package_if_needed "amule"
    install_package_if_needed "amule-utils"
    install_package_if_needed "amule-daemon"
    install_package_if_needed "amule-utils-gui"
    install_package_if_needed "jq"
    install_package_if_needed "curl"

    log "INFO" "aMule y sus dependencias instaladas correctamente."
}

#######################################
# Función para crear el usuario amule
#######################################
create_amule_user() {
    if id "$usuario" &>/dev/null; then
        log "INFO" "El usuario '$usuario' ya existe. Saltando creación."
    else
        log "INFO" "Creando usuario '$usuario'..."
        sudo adduser --disabled-login --gecos "" "$usuario"
        log "INFO" "Usuario '$usuario' creado correctamente."
    fi

    # Crear el directorio home si no existe
    if [[ ! -d "$user_home" ]]; then
        log "INFO" "Creando directorio home para '$usuario' en '$user_home'..."
        sudo mkdir -p "$user_home"
        sudo chown "$usuario":"$usuario" "$user_home"
        log "INFO" "Directorio home creado y propietarios establecidos."
    else
        log "INFO" "El directorio home '$user_home' ya existe. Verificando permisos..."
        sudo chown "$usuario":"$usuario" "$user_home"
    fi
}

#######################################
# Función para configurar /etc/default/amule-daemon
#######################################
configure_amule_daemon_defaults() {
    local default_file="/etc/default/amule-daemon"

    log "INFO" "Configurando '$default_file'..."

    # Crear o sobrescribir el archivo con las configuraciones necesarias
    cat > "$default_file" << EOF
# Configuración para amule-daemon

# Usuario que ejecutará amuled
AMULED_USER="$usuario"

# Directorio home del usuario
AMULED_HOME="$user_home"
EOF

    log "INFO" "Archivo '$default_file' configurado correctamente."
}

#######################################
# Función para crear directorios necesarios
# Argumentos:
#   $1 - Directorio de incoming
#   $2 - Directorio temporal
#######################################
create_directories() {
    local incoming_dir="$1"
    local temp_dir="$2"

    log "INFO" "Creando directorios de aMule si no existen..."

    # Verificar si los directorios padre existen
    if [[ ! -d "$(dirname "$incoming_dir")" ]]; then
        log "ERROR" "El directorio padre del directorio incoming no existe: $(dirname "$incoming_dir")"
        exit 1
    fi

    if [[ ! -d "$(dirname "$temp_dir")" ]]; then
        log "ERROR" "El directorio padre del directorio temporal no existe: $(dirname "$temp_dir")"
        exit 1
    fi

    # Crear directorios
    mkdir -p "$incoming_dir" "$temp_dir"

    # Verificar si los directorios son escribibles
    if [[ ! -w "$incoming_dir" ]]; then
        log "ERROR" "El directorio incoming no es escribible: $incoming_dir"
        exit 1
    fi

    if [[ ! -w "$temp_dir" ]]; then
        log "ERROR" "El directorio temporal no es escribible: $temp_dir"
        exit 1
    fi

    log "INFO" "Estableciendo permisos y propietarios para los directorios..."
    chown -R "$usuario":"$usuario" "$incoming_dir" "$temp_dir"
    chmod -R 755 "$incoming_dir" "$temp_dir"

    log "INFO" "Directorios de aMule creados y permisos establecidos."
}

#######################################
# Función para actualizar o agregar una clave en una sección INI
# Argumentos:
#   $1 - Archivo
#   $2 - Sección
#   $3 - Clave
#   $4 - Valor
#######################################
update_ini() {
    local file="$1"
    local section
    local key
    local value

    # Escapar caracteres especiales
    section="$(printf '%s\n' "$2" | sed 's/[][\/.^$*]/\\&/g')"
    key="$(printf '%s\n' "$3" | sed 's/[][\/.^$*]/\\&/g')"
    value="$(printf '%s\n' "$4" | sed 's/[\/&]/\\&/g')"

    if grep -q "^\[$section\]" "$file"; then
        if grep -A1000 "^\[$section\]" "$file" | grep -m1 -q "^$key="; then
            # Actualizar clave existente
            sed -i "/^\[$section\]/,/^\[/{s|^$key=.*|$key=$value|}" "$file"
        else
            # Agregar clave al final de la sección
            sed -i "/^\[$section\]/a $key=$value" "$file"
        fi
    else
        # Agregar sección y clave al final del archivo
        echo -e "\n[$section]\n$key=$value" >> "$file"
    fi
}

#######################################
# Función para generar y configurar amule.conf
# Argumentos:
#   $1 - Contraseña del cliente
#   $2 - Directorio incoming
#   $3 - Directorio temporal
#######################################
configure_amule() {
    local password_client="$1"
    local incoming_dir="$2"
    local temp_dir="$3"

    log "INFO" "Generando archivo de configuración amule.conf..."

    local amule_conf="$user_home/.aMule/amule.conf"
    local pid_file="$user_home/.aMule/amuled.pid"

    # Crear directorio .aMule si no existe
    if [[ ! -d "$user_home/.aMule" ]]; then
        log "INFO" "Creando directorio '$user_home/.aMule'..."
        sudo -u "$usuario" mkdir -p "$user_home/.aMule"
        sudo -u "$usuario" chown -R "$usuario":"$usuario" "$user_home/.aMule"
    fi

    # Ejecutar amuled para generar el archivo de configuración si no existe
    if [[ ! -f "$amule_conf" ]]; then
        log "INFO" "Generando archivos de configuración de aMule..."
        sudo -u "$usuario" amuled --ec-config --config-dir="$user_home/.aMule" &
        local amuled_pid=$!
        sleep 5

        # Detener amuled de forma segura
        if [[ -f "$pid_file" ]]; then
            kill -TERM "$(cat "$pid_file")"
            wait "$amuled_pid"
            log "INFO" "Archivos de configuración generados y amuled detenido."
        else
            log "WARNING" "Archivo PID no encontrado. Matando proceso de amuled."
            kill "$amuled_pid" || true
        fi
    else
        log "INFO" "El archivo de configuración amule.conf ya existe. Saltando generación inicial."
    fi

    # Realizar una copia de seguridad si no existe
    if [[ ! -f "${amule_conf}.backup" ]]; then
        log "INFO" "Creando copia de seguridad de amule.conf..."
        cp "$amule_conf" "${amule_conf}.backup"
        log "INFO" "Copia de seguridad creada."
    else
        log "INFO" "Copia de seguridad de amule.conf ya existe. Saltando."
    fi

    # Generar hash MD5 de las contraseñas
    local password_client_md5
    local password_web_md5
    password_client_md5=$(echo -n "$password_client" | md5sum | awk '{print $1}')

    # Leer la contraseña de la web desde el archivo JSON o generar una
    local web_password
    if jq -e '.web_password' "$creds_json" &>/dev/null; then
        web_password=$(jq -r '.web_password' "$creds_json")
    else
        # Generar una contraseña aleatoria si no está definida
        web_password=$(openssl rand -base64 12)
        jq --arg pwd "$web_password" '.web_password = $pwd' "$creds_json" > "${creds_json}.tmp" && mv "${creds_json}.tmp" "$creds_json"
        log "INFO" "Generada una contraseña aleatoria para la web de aMule."
    fi
    password_web_md5=$(echo -n "$web_password" | md5sum | awk '{print $1}')

    # Actualizar configuraciones en amule.conf
    log "INFO" "Actualizando configuraciones en amule.conf..."

    # Actualizar configuraciones necesarias
    update_ini "$amule_conf" "eMule" "IncomingDir" "$incoming_dir"
    update_ini "$amule_conf" "eMule" "TempDir" "$temp_dir"
    update_ini "$amule_conf" "eMule" "Template" "webserver"
    update_ini "$amule_conf" "eMule" "Password" "$password_client_md5"
    update_ini "$amule_conf" "eMule" "UserNick" "$usuario"
    update_ini "$amule_conf" "eMule" "AcceptExternalConnections" "1"

    # Configurar el WebServer
    update_ini "$amule_conf" "WebServer" "Enabled" "1"
    update_ini "$amule_conf" "WebServer" "Port" "8090"
    update_ini "$amule_conf" "WebServer" "Password" "$password_web_md5"

    # Configurar ExternalConnect
    update_ini "$amule_conf" "ExternalConnect" "ECPassword" "$password_client_md5"

    # Establecer permisos adecuados en el archivo de configuración
    chown "$usuario":"$usuario" "$amule_conf"
    chmod 600 "$amule_conf"

    log "INFO" "Configuraciones actualizadas en amule.conf."
}

#######################################
# Función para configurar el servicio init.d de aMule
#######################################
configure_initd_service() {
    log "INFO" "Configurando el servicio init.d de aMule..."

    # Reiniciar el servicio para aplicar cambios en /etc/default/amule-daemon
    service amule-daemon restart

    log "INFO" "Servicio init.d de aMule configurado y reiniciado."
}

#######################################
# Función para configurar servicios systemd para la GUI (opcional)
# Nota: La GUI puede no ser necesaria si solo se usa la interfaz web
#######################################
configure_services_gui() {
    log "INFO" "Configurando servicios systemd para la GUI de aMule (si es necesario)..."

    # Crear archivo de servicio para aMule GUI
    cat > /etc/systemd/system/amule-gui.service << EOF
[Unit]
Description=aMule GUI
After=amule-daemon.service

[Service]
Type=simple
User=$usuario
Group=$usuario
Environment=DISPLAY=:0
Environment=HOME=$user_home
ExecStart=/usr/bin/amule
Restart=on-failure

[Install]
WantedBy=graphical.target
EOF

    log "INFO" "Archivo de servicio systemd para aMule GUI creado."

    # Recargar systemd y habilitar el servicio GUI
    systemctl daemon-reload
    systemctl enable amule-gui.service

    log "INFO" "Servicio aMule GUI habilitado."
}

#######################################
# Función para habilitar y arrancar servicios
#######################################
enable_and_start_services() {
    log "INFO" "Recargando systemd para reconocer los nuevos servicios..."
    systemctl daemon-reload

    log "INFO" "Habilitando servicios de aMule para que se inicien al arrancar..."
    systemctl enable amule-daemon.service

    log "INFO" "Iniciando servicios de aMule..."
    systemctl restart amule-daemon.service

    # Verificar el estado del servicio aMule
    if systemctl is-active --quiet amule-daemon.service; then
        log "INFO" "Servicio amule-daemon.service iniciado correctamente."
    else
        log "ERROR" "Fallo al iniciar amule-daemon.service. Revisa los logs para más detalles."
        journalctl -u amule-daemon.service --no-pager
        exit 1
    fi

    # Si se configuró la GUI, iniciar y verificar
    if [[ -f "/etc/systemd/system/amule-gui.service" ]]; then
        systemctl enable amule-gui.service
        systemctl restart amule-gui.service

        if systemctl is-active --quiet amule-gui.service; then
            log "INFO" "Servicio amule-gui.service iniciado correctamente."
        else
            log "ERROR" "Fallo al iniciar amule-gui.service. Revisa los logs para más detalles."
            journalctl -u amule-gui.service --no-pager
            exit 1
        fi
    fi

    log "INFO" "Servicios de aMule iniciados correctamente."
}

#######################################
# Función principal
#######################################
main() {
    log "INFO" "Ejecutando '/opt/confiraspa/install_amule.sh'..."

    # Verificar si se ejecuta como root
    check_root

    # Verificar conectividad a Internet
    check_internet

    # Verificar que los archivos JSON existen
    if [[ ! -f "$creds_json" ]]; then
        log "ERROR" "El archivo de credenciales no existe: $creds_json"
        exit 1
    fi

    if [[ ! -f "$dirs_json" ]]; then
        log "ERROR" "El archivo de directorios no existe: $dirs_json"
        exit 1
    fi

    # Leer la contraseña desde el archivo JSON
    local contrasena
    contrasena=$(jq -r '.password' "$creds_json")

    # Leer la contraseña de la web desde el archivo JSON (opcional)
    local web_password
    if jq -e '.web_password' "$creds_json" &>/dev/null; then
        web_password=$(jq -r '.web_password' "$creds_json")
    else
        # Generar una contraseña aleatoria si no está definida
        web_password=$(openssl rand -base64 12)
        jq --arg pwd "$web_password" '.web_password = $pwd' "$creds_json" > "${creds_json}.tmp" && mv "${creds_json}.tmp" "$creds_json"
        log "INFO" "Generada una contraseña aleatoria para la web de aMule."
    fi

    # Crear el usuario amule
    create_amule_user

    # Proteger el archivo de credenciales
    chmod 600 "$creds_json"
    chown "$usuario":"$usuario" "$creds_json"

    # Leer directorios desde el archivo JSON
    local incoming_directory
    local temp_directory
    incoming_directory=$(jq -r '.incoming_directory' "$dirs_json")
    temp_directory=$(jq -r '.temp_directory' "$dirs_json")

    # Instalar aMule y dependencias
    install_amule

    # Configurar /etc/default/amule-daemon
    configure_amule_daemon_defaults

    # Crear directorios necesarios
    create_directories "$incoming_directory" "$temp_directory"

    # Configurar aMule
    configure_amule "$contrasena" "$incoming_directory" "$temp_directory"

    # Configurar el servicio init.d de aMule
    configure_initd_service

    # (Opcional) Configurar servicios systemd para la GUI de aMule
    # Uncomment the following line if deseas configurar la GUI
    # configure_services_gui

    # Habilitar y arrancar servicios
    enable_and_start_services

    log "INFO" "Instalación y configuración de aMule completada exitosamente."
}

# Ejecutar la función principal
main
