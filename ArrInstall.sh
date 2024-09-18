#!/bin/bash
### Description: Instalación automatizada de todas las aplicaciones \*Arr
### Modificado para instalar todas las aplicaciones sin solicitar selección al usuario
### Lee el usuario y grupo desde /configs/arr_user.json

scriptversion="4.0.0"
scriptdate="2023-10-05"

set -euo pipefail

# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

log "INFO" "Ejecutando el script de instalación de todas las aplicaciones \*Arr - Versión [$scriptversion] - Fecha [$scriptdate]"

# Verificar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    log "ERROR" "Este script debe ser ejecutado con privilegios de superusuario (sudo)."
    exit 1
fi

# Definir las aplicaciones a instalar
apps=("lidarr" "prowlarr" "radarr" "readarr" "whisparr")

# Leer usuario y grupo desde el archivo JSON en /configs
config_dir="/configs"
json_file="$config_dir/arr_user.json"

# Verificar si el archivo JSON existe
if [ ! -f "$json_file" ]; then
    log "ERROR" "El archivo de configuración $json_file no se encuentra."
    exit 1
fi

# Verificar si 'jq' está instalado
if ! command -v jq >/dev/null 2>&1; then
    log "INFO" "Instalando 'jq'..."
    apt-get update
    apt-get install -y jq
fi

# Leer usuario y grupo desde el archivo JSON
app_uid=$(jq -r '.user' "$json_file")
app_guid=$(jq -r '.group' "$json_file")

# Validar que los valores no estén vacíos
if [ -z "$app_uid" ] || [ -z "$app_guid" ]; then
    log "ERROR" "El archivo $json_file no contiene el usuario o grupo."
    exit 1
fi

log "INFO" "Las aplicaciones se instalarán y ejecutarán como el usuario [$app_uid] y el grupo [$app_guid]."

# Crear usuario y grupo si es necesario
if ! getent group "$app_guid" >/dev/null; then
    log "INFO" "Creando grupo [$app_guid]..."
    groupadd "$app_guid"
fi

if ! id -u "$app_uid" >/dev/null 2>&1; then
    log "INFO" "Creando usuario [$app_uid] y agregándolo al grupo [$app_guid]..."
    adduser --system --no-create-home --ingroup "$app_guid" "$app_uid"
fi

if ! id -nG "$app_uid" | grep -qw "$app_guid"; then
    log "INFO" "Agregando usuario [$app_uid] al grupo [$app_guid]..."
    usermod -a -G "$app_guid" "$app_uid"
fi

# Directorio de instalación
installdir="/opt"

# Instalar paquetes comunes necesarios para todas las aplicaciones
log "INFO" "Actualizando lista de paquetes e instalando paquetes comunes necesarios..."
apt-get update
apt-get install -y curl sqlite3

# Función para instalar una aplicación
install_app() {
    local app="$1"
    case $app in
    lidarr)
        app_port="8686"
        app_prereq="libchromaprint-tools mediainfo"
        app_umask="0002"
        branch="master"
        ;;
    prowlarr)
        app_port="9696"
        app_prereq=""
        app_umask="0002"
        branch="develop"
        ;;
    radarr)
        app_port="7878"
        app_prereq=""
        app_umask="0002"
        branch="master"
        ;;
    readarr)
        app_port="8787"
        app_prereq=""
        app_umask="0002"
        branch="develop"
        ;;
    whisparr)
        app_port="6969"
        app_prereq=""
        app_umask="0002"
        branch="nightly"
        ;;
    *)
        log "ERROR" "Aplicación desconocida: $app"
        return 1
        ;;
    esac

    bindir="${installdir}/${app^}"
    datadir="/var/lib/$app/"
    app_bin=${app^}

    log "INFO" "Instalando ${app^}..."

    # Instalar paquetes específicos de la aplicación
    if [ -n "$app_prereq" ]; then
        log "INFO" "Instalando paquetes necesarios para ${app^}..."
        apt-get install -y $app_prereq
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
    tar -xzf "$temp_dir"/${app^}.*.tar.gz -C "$temp_dir"

    # Detener la aplicación si está en ejecución
    if systemctl list-units --type=service --state=active | grep -Fq "$app.service"; then
        log "INFO" "Deteniendo el servicio $app..."
        systemctl stop "$app"
        systemctl disable "$app.service"
    fi

    # Verificar si ya existe una instalación
    if [ -d "$bindir" ]; then
        log "INFO" "Realizando copia de seguridad de la instalación existente..."
        mv "$bindir" "${bindir}_backup_$(date +%Y%m%d%H%M%S)"
    fi

    # Instalar la aplicación
    log "INFO" "Instalando ${app^} en [$bindir]..."
    mv "$temp_dir/${app^}" "$bindir"
    chown -R "$app_uid":"$app_guid" "$bindir"
    chmod 775 "$bindir"

    # Limpiar archivos temporales
    rm -rf "$temp_dir"

    # Crear directorio de datos
    log "INFO" "Creando directorio de datos en [$datadir]..."
    mkdir -p "$datadir"
    chown -R "$app_uid":"$app_guid" "$datadir"
    chmod 775 "$datadir"

    # Asegurar que se verifique si hay actualizaciones
    touch "$datadir/update_required"
    chown "$app_uid":"$app_guid" "$datadir/update_required"

    # Crear archivo de servicio systemd
    service_file="/etc/systemd/system/$app.service"
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

    # Recargar daemon de systemd y habilitar el servicio
    log "INFO" "Habilitando e iniciando el servicio $app..."
    systemctl daemon-reload
    systemctl enable "$app"
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

# Instalar cada aplicación
for app in "${apps[@]}"; do
    install_app "$app" || log "ERROR" "Error al instalar $app"
done

log "INFO" "Todas las aplicaciones \*Arr han sido instaladas."

exit 0


