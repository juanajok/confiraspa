#!/bin/bash
### Description: Instalación automatizada de todas las aplicaciones *Arr
### Modificado para instalar todas las aplicaciones sin solicitar selección al usuario
### Lee el usuario y grupo desde /opt/confiraspa/configs/arr_user.json

scriptversion="4.0.0"
scriptdate="2023-10-05"

set -euo pipefail

# Variables
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CONFIG_DIR="$SCRIPT_DIR/configs"
JSON_FILE="$CONFIG_DIR/arr_user.json"
LOG_DIR="/var/log/confiraspi_v5"
INSTALL_DIR="/opt"
COMMON_PACKAGES=("curl" "sqlite3")
APPS=("lidarr" "prowlarr" "radarr" "readarr" "whisparr")

# Crear el directorio de logs si no existe
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"

# Definir archivo de log para este script
SCRIPT_LOG_FILE="$LOG_DIR/install_arr.sh.log"

# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log() {
    local level="$1"
    local message="$2"
    printf "[%s] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$message" >> "$SCRIPT_LOG_FILE"
}

# Función para verificar si se ejecuta como root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "Este script debe ejecutarse con privilegios de superusuario (sudo)."
        exit 1
    fi
}

# Función para verificar y crear usuario y grupo
setup_user_group() {
    local user="$1"
    local group="$2"

    # Verificar y crear grupo si no existe
    if ! getent group "$group" > /dev/null 2>&1; then
        log "INFO" "Creando grupo [$group]..."
        groupadd "$group"
    else
        log "INFO" "El grupo [$group] ya existe."
    fi

    # Verificar y crear usuario si no existe
    if ! id -u "$user" > /dev/null 2>&1; then
        log "INFO" "Creando usuario [$user] y agregándolo al grupo [$group]..."
        adduser --system --no-create-home --ingroup "$group" "$user"
    else
        log "INFO" "El usuario [$user] ya existe."
    fi

    # Asegurar que el usuario está en el grupo
    if ! id -nG "$user" | grep -qw "$group"; then
        log "INFO" "Agregando usuario [$user] al grupo [$group]..."
        usermod -a -G "$group" "$user"
    else
        log "INFO" "El usuario [$user] ya está en el grupo [$group]."
    fi
}

# Función para instalar paquetes comunes
install_common_packages() {
    log "INFO" "Instalando paquetes comunes: ${COMMON_PACKAGES[*]}..."
    apt-get update
    apt-get install -y "${COMMON_PACKAGES[@]}"
}

# Función para verificar si una aplicación ya está instalada
is_app_installed() {
    local app="$1"
    local bindir="${INSTALL_DIR}/${app^}"
    if [ -d "$bindir" ]; then
        return 0
    else
        return 1
    fi
}

# Función para instalar una aplicación
install_app() {
    local app="$1"
    local app_port app_prereq app_umask branch bindir datadir app_bin ARCH DLURL dlbase temp_dir service_file host

    case $app in
        lidarr)
            app_port="8686"
            app_prereq=("libchromaprint-tools" "mediainfo")
            app_umask="0002"
            branch="master"
            ;;
        prowlarr)
            app_port="9696"
            app_prereq=()
            app_umask="0002"
            branch="develop"
            ;;
        radarr)
            app_port="7878"
            app_prereq=()
            app_umask="0002"
            branch="master"
            ;;
        readarr)
            app_port="8787"
            app_prereq=()
            app_umask="0002"
            branch="develop"
            ;;
        whisparr)
            app_port="6969"
            app_prereq=()
            app_umask="0002"
            branch="nightly"
            ;;
        *)
            log "ERROR" "Aplicación desconocida: $app"
            return 1
            ;;
    esac

    bindir="${INSTALL_DIR}/${app^}"
    datadir="/var/lib/$app/"
    app_bin="${app^}"

    # Verificar si la aplicación ya está instalada
    if is_app_installed "$app"; then
        log "INFO" "${app^} ya está instalada en [$bindir]. Saltando instalación."
        return 0
    fi

    log "INFO" "Instalando ${app^}..."

    # Instalar paquetes específicos de la aplicación
    if [ ${#app_prereq[@]} -gt 0 ]; then
        log "INFO" "Instalando paquetes necesarios para ${app^}: ${app_prereq[*]}..."
        apt-get install -y "${app_prereq[@]}"
    fi

    # Obtener la arquitectura del sistema
    ARCH=$(dpkg --print-architecture)

    # Construir la URL de descarga
    dlbase="https://$app.servarr.com/v1/update/$branch/updatefile?os=linux&runtime=netcore"
    case "$ARCH" in
        "amd64") DLURL="${dlbase}&arch=x64" ;;
        "armhf") DLURL="${dlbase}&arch=arm" ;;
        "arm64") DLURL="${dlbase}&arch=arm64" ;;
        *)
            log "ERROR" "Arquitectura no soportada: $ARCH"
            return 1
            ;;
    esac

    # Descarga e instalación de la aplicación
    log "INFO" "Descargando ${app^} desde $DLURL..."
    temp_dir=$(mktemp -d)
    wget --content-disposition "$DLURL" -P "$temp_dir"

    log "INFO" "Extrayendo archivos..."
    tar -xzf "$temp_dir"/*"${app^}"*.tar.gz -C "$temp_dir"

    # Detener la aplicación si está en ejecución
    if systemctl list-units --type=service --state=active | grep -Fq "$app.service"; then
        log "INFO" "Deteniendo el servicio $app..."
        systemctl stop "$app"
        systemctl disable "$app.service"
    fi

    # Verificar si ya existe una instalación (redundante por idempotencia)
    if [ -d "$bindir" ]; then
        log "INFO" "Realizando copia de seguridad de la instalación existente en [$bindir]..."
        mv "$bindir" "${bindir}_backup_$(date +%Y%m%d%H%M%S)"
    fi

    # Instalar la aplicación
    log "INFO" "Instalando ${app^} en [$bindir]..."
    mv "$temp_dir/${app^}" "$bindir"
    chown -R "$app_uid":"$app_guid" "$bindir"
    chmod 775 "$bindir"

    # Limpiar archivos temporales
    rm -rf "$temp_dir"

    # Crear directorio de datos si no existe
    if [ ! -d "$datadir" ]; then
        log "INFO" "Creando directorio de datos en [$datadir]..."
        mkdir -p "$datadir"
        chown -R "$app_uid":"$app_guid" "$datadir"
        chmod 775 "$datadir"
    else
        log "INFO" "El directorio de datos [$datadir] ya existe."
    fi

    # Crear archivo de servicio systemd
    service_file="/etc/systemd/system/$app.service"
    if [ ! -f "$service_file" ]; then
        log "INFO" "Creando archivo de servicio systemd en [$service_file]..."
        cat <<EOF > "$service_file"
[Unit]
Description=${app^} Daemon
After=network.target

[Service]
User=$app_uid
Group=$app_guid
UMask=$app_umask
Type=simple
ExecStart=$bindir/$app_bin -nobrowser -data=$datadir
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    else
        log "INFO" "El archivo de servicio systemd [$service_file] ya existe. Actualizando configuración si es necesario."
        # Puedes agregar lógica aquí para actualizar el archivo de servicio si ha cambiado
    fi

    # Recargar daemon de systemd y habilitar el servicio
    log "INFO" "Recargando el daemon de systemd..."
    systemctl daemon-reload

    if ! systemctl is-enabled "$app" > /dev/null 2>&1; then
        log "INFO" "Habilitando el servicio $app..."
        systemctl enable "$app"
    else
        log "INFO" "El servicio $app ya está habilitado."
    fi

    log "INFO" "Iniciando el servicio $app..."
    systemctl start "$app"

    # Verificar el estado del servicio
    sleep 10
    if systemctl is-active --quiet "$app"; then
        host=$(hostname -I | awk '{print $1}')
        log "INFO" "${app^} instalado y ejecutándose correctamente."
        log "INFO" "Accede a la interfaz web en http://$host:$app_port"
    else
        log "ERROR" "${app^} no se está ejecutando correctamente."
        systemctl status "$app"
        return 1
    fi

    return 0
}

# Función principal
main() {
    log "INFO" "Iniciando el script de instalación de todas las aplicaciones *Arr..."

    # Verificar si se ejecuta como root
    check_root

    # Verificar si el archivo JSON existe
    if [ ! -f "$JSON_FILE" ]; then
        log "ERROR" "El archivo de configuración $JSON_FILE no se encuentra."
        exit 1
    fi

    # Verificar si 'jq' está instalado (redundante si ya se instala en el script principal)
    if ! command -v jq >/dev/null 2>&1; then
        log "INFO" "Instalando 'jq'..."
        apt-get update
        apt-get install -y jq
    fi

    # Leer usuario y grupo desde el archivo JSON
    app_uid=$(jq -r '.user' "$JSON_FILE")
    app_guid=$(jq -r '.group' "$JSON_FILE")

    # Validar que los valores no estén vacíos
    if [ -z "$app_uid" ] || [ -z "$app_guid" ]; then
        log "ERROR" "El archivo $JSON_FILE no contiene el usuario o grupo."
        exit 1
    fi

    log "INFO" "Las aplicaciones se instalarán y ejecutarán como el usuario [$app_uid] y el grupo [$app_guid]."

    # Configurar usuario y grupo
    setup_user_group "$app_uid" "$app_guid"

    # Instalar paquetes comunes
    install_common_packages

    # Instalar cada aplicación
    for app in "${APPS[@]}"; do
        install_app "$app" || log "ERROR" "Error al instalar $app"
    done

    log "INFO" "Todas las aplicaciones *Arr han sido instaladas."
}

# Llamar a la función principal
main
