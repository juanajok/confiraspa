#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t' # Buena práctica, aunque menos crítica aquí

# Script Name: install_amule.sh
# Description: Instalación automatizada y segura de aMule (daemon) en Raspbian OS (para RPi 5)
# Version: 3.1.0 (Revisado)
# License: MIT
# Usage: sudo ./install_amule.sh (Asegúrate que /opt/confiraspa/lib/utils.sh existe y configura CONFIG_DIR/LOG_DIR)

# --- Cargar Funciones Comunes ---
# Asegúrate que este script existe y define las funciones/variables necesarias
# (log, check_root, setup_error_handling, setup_paths, check_network_connectivity,
# install_packages, get_ip_address, CONFIG_DIR, LOG_DIR)
if [[ ! -f "/opt/confiraspa/lib/utils.sh" ]]; then
    echo "ERROR: Script de utilidades '/opt/confiraspa/lib/utils.sh' no encontrado." >&2
    exit 1
fi
source /opt/confiraspa/lib/utils.sh

# --- Configuración Global ---
readonly AMULE_USER="amule"
# Usar /var/lib/amule es estándar para los datos del daemon
readonly AMULE_HOME="/var/lib/amule"
readonly WEBUI_PORT=4711
readonly CONTROL_PORT=4712
readonly SSL_CERT_DIR="/etc/ssl/amule"
readonly SSL_CERT_FILE="${SSL_CERT_DIR}/amule-webui.crt"
readonly SSL_KEY_FILE="${SSL_CERT_DIR}/amule-webui.key"

# Variables que dependen de utils.sh (CONFIG_DIR, LOG_DIR)
# Asegúrate que setup_paths() las define correctamente antes de usarlas.
CREDENTIALS_FILE="" # Se definirá después de llamar a setup_paths
LOG_FILE=""         # Se definirá después de llamar a setup_paths

# --- Funciones Principales ---

main() {
    initialize_installation # Incluye setup_paths que define CONFIG_DIR/LOG_DIR

    # Definir rutas que dependen de CONFIG_DIR/LOG_DIR ahora
    CREDENTIALS_FILE="${CONFIG_DIR}/credenciales.json" # Nombre de archivo sugerido
    LOG_FILE="${LOG_DIR}/amule_install.log"

    validate_credentials
    install_dependencies 
    setup_system_user
    configure_filesystem
    install_ssl_certificate
    configure_firewall
    configure_amule # Ahora maneja /etc/default y llama a configure_amule_conf
    enable_services
    final_checks
}

initialize_installation() {
    check_root
    setup_error_handling # Configura traps de error
    # Llama a setup_paths AQUI para que CONFIG_DIR/LOG_DIR estén disponibles
    setup_paths || { echo "ERROR: Fallo en setup_paths de utils.sh" >&2; exit 1; }
    check_network_connectivity
    log "INFO" "Iniciando instalación de aMule Daemon"
    # Crear directorio de log si no existe (utils.sh podría hacerlo)
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
}

validate_credentials() {
    log "INFO" "Validando archivo de credenciales: ${CREDENTIALS_FILE}"

    [[ -f "$CREDENTIALS_FILE" ]] || {
        log "ERROR" "Archivo de credenciales no encontrado: $CREDENTIALS_FILE"
        log "ERROR" "Crea un archivo JSON en esa ruta con el formato: { \"password\": \"tu_pass_control\", \"web_password\": \"tu_pass_webui\" }"
        exit 1
    }

    # Validar que las claves necesarias existen y no están vacías
    if ! jq -e '
        (.password and (.password | length > 0)) and
        (.web_password and (.web_password | length > 0))
        ' "$CREDENTIALS_FILE" >/dev/null; then
        log "ERROR" "Estructura inválida o valores vacíos en $CREDENTIALS_FILE. Requiere 'password' y 'web_password'."
        exit 1
    fi

    chmod 600 "$CREDENTIALS_FILE" || log "WARN" "No se pudo cambiar permisos de $CREDENTIALS_FILE"
    log "INFO" "Credenciales validadas correctamente."
}

install_required_packages() {
    log "INFO" "Instalando dependencias y paquetes de aMule..."
    # Asegúrate que jq está incluido para validar credenciales
    # python3-pycurl no parece ser necesario para amule-daemon/utils, eliminar si no se usa.
    local packages_to_install=(
        "amule-daemon"
        "amule-utils" # Para amulecmd
        "ufw"         # Firewall
        "openssl"     # Para generar certificado
        "jq"          # Para leer credenciales
    )
    install_packages "${packages_to_install[@]}" || {
        log "ERROR" "Fallo al instalar paquetes requeridos."
        exit 1
    }
}

setup_system_user() {
    if id -u "${AMULE_USER}" &>/dev/null; then
        log "INFO" "Usuario del sistema '${AMULE_USER}' ya existe."
    else
        log "INFO" "Creando usuario del sistema dedicado: ${AMULE_USER}"
        # Usuario de sistema (-r), pertenece a su propio grupo primario (-g ${AMULE_USER} implícito con --group), sin shell de login, home especificado
        useradd --system --group --shell /bin/false --home-dir "${AMULE_HOME}" "${AMULE_USER}" || {
            log "ERROR" "Fallo al crear usuario del sistema '${AMULE_USER}'"
            exit 1
        }
        log "INFO" "Usuario '${AMULE_USER}' creado."
    fi
}

configure_filesystem() {
    log "INFO" "Configurando directorios y permisos en ${AMULE_HOME}"
    # Directorios estándar de aMule dentro de su HOME
    local dirs=("${AMULE_HOME}" "${AMULE_HOME}/Incoming" "${AMULE_HOME}/Temp")

    for dir in "${dirs[@]}"; do
        # Crear directorio si no existe
        mkdir -p "${dir}" || { log "ERROR" "No se pudo crear directorio: ${dir}"; exit 1; }
        # Establecer propietario y grupo
        chown "${AMULE_USER}:${AMULE_USER}" "${dir}" || log "WARN" "No se pudo cambiar propietario de ${dir}"
        # Permisos: Usuario=rwx, Grupo=rx, Otros=--- (seguro)
        chmod 750 "${dir}" || log "WARN" "No se pudo cambiar permisos de ${dir}"
    done
    log "INFO" "Sistema de archivos configurado para ${AMULE_USER}."
}

install_ssl_certificate() {
    log "INFO" "Verificando/Generando certificado SSL para WebUI..."
    if [[ -f "${SSL_CERT_FILE}" && -f "${SSL_KEY_FILE}" ]]; then
        log "INFO" "Certificado SSL existente encontrado en ${SSL_CERT_DIR}."
        # Podríamos añadir una verificación de validez/expiración aquí si quisiéramos
    else
        log "INFO" "Generando nuevo certificado SSL autofirmado (válido por 10 años)."
        mkdir -p "${SSL_CERT_DIR}" || { log "ERROR" "No se pudo crear directorio ${SSL_CERT_DIR}"; exit 1; }

        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "${SSL_KEY_FILE}" \
            -out "${SSL_CERT_FILE}" \
            -subj "/CN=aMuleWebUI" || {
            log "ERROR" "Fallo al generar certificado SSL."
            # Limpiar archivos parciales si falla
            rm -f "${SSL_KEY_FILE}" "${SSL_CERT_FILE}"
            exit 1
        }

        # Establecer permisos seguros en la clave privada
        chown root:"${AMULE_USER}" "${SSL_KEY_FILE}" || log "WARN" "No se pudo cambiar propietario de ${SSL_KEY_FILE}"
        chmod 640 "${SSL_KEY_FILE}" || log "WARN" "No se pudo cambiar permisos de ${SSL_KEY_FILE}"
        log "INFO" "Certificado SSL generado y permisos aplicados."
    fi
     # Asegurar permisos del certificado público también (menos crítico)
     chown root:"${AMULE_USER}" "${SSL_CERT_FILE}" || log "WARN" "No se pudo cambiar propietario de ${SSL_CERT_FILE}"
     chmod 644 "${SSL_CERT_FILE}" || log "WARN" "No se pudo cambiar permisos de ${SSL_CERT_FILE}"
}

configure_firewall() {
    log "INFO" "Configurando reglas de firewall con UFW..."

    if ! command -v ufw &> /dev/null; then
        log "WARN" "Comando 'ufw' no encontrado. Saltando configuración de firewall."
        return 1 # Devuelve un código de error
    fi

    # Habilitar UFW si está inactivo
    if ufw status | grep -qw inactive; then
        log "INFO" "UFW está inactivo. Habilitando..."
        # Usar yes para evitar prompt interactivo si es la primera vez
        if yes | ufw enable; then
            log "INFO" "UFW habilitado correctamente."
        else
            log "ERROR" "No se pudo habilitar UFW automáticamente. Revisa los permisos o hazlo manualmente."
            return 1 # Devuelve un código de error si no se puede habilitar
        fi
    fi

    log "INFO" "Aplicando reglas de firewall..."

    # --- Reglas Esenciales ---
    log "INFO" "Permitiendo SSH (puerto 22)..."
    ufw allow 22/tcp comment 'SSH remote access'

    # --- Reglas para NAS y Compartición de Archivos ---
    log "INFO" "Permitiendo Samba (puertos 137, 138, 139, 445)..."
    ufw allow 137/udp comment 'Samba NetBIOS Name Service'
    ufw allow 138/udp comment 'Samba NetBIOS Datagram Service'
    ufw allow 139/tcp comment 'Samba NetBIOS Session Service'
    ufw allow 445/tcp comment 'Samba SMB/CIFS'
    # Opcional: NFS (si lo usas)
    # log "INFO" "Permitiendo NFS (puerto 2049)..."
    # ufw allow 2049 comment 'NFS'
    # Nota: NFS puede requerir puertos adicionales para rpcbind y mountd.

    # --- Reglas para Acceso Remoto y Administración ---
    log "INFO" "Permitiendo XRDP (puerto 3389)..."
    ufw allow 3389/tcp comment 'XRDP Remote Desktop'
    log "INFO" "Permitiendo Webmin (puerto 10000)..."
    ufw allow 10000/tcp comment 'Webmin web administration'
    log "INFO" "Permitiendo VNC (puerto 5900)..."
    ufw allow 5900/tcp comment 'VNC default display :0'
    # Si usas VNC en otros displays (ej: :1), necesitarás abrir 5901, etc.

    # --- Reglas para Aplicaciones de Descarga ---
    log "INFO" "Permitiendo aMule (puertos 4662, 4672, WebUI, Control)..."
    ufw allow 4662/tcp comment 'aMule incoming TCP'
    ufw allow 4672/udp comment 'aMule Kademlia UDP'
    ufw allow "${WEBUI_PORT}/tcp" comment 'aMule WebUI TCP'
    ufw allow "${CONTROL_PORT}/tcp" comment 'aMule Control TCP'

    log "INFO" "Permitiendo Transmission (puertos 9091, 51413)..."
    ufw allow 9091/tcp comment 'Transmission Web UI'
    ufw allow 51413/tcp comment 'Transmission Peer Port TCP'
    ufw allow 51413/udp comment 'Transmission Peer Port UDP/DHT'
    # Nota: El puerto de peers (51413) puede ser configurable en Transmission.

    # --- Reglas para Servidores Multimedia y Automatización (*arr stack) ---
    log "INFO" "Permitiendo Plex Media Server (puertos 32400, discovery)..."
    ufw allow 32400/tcp comment 'Plex Media Server Web UI & API'
    # Puertos para descubrimiento en red local (GDM, DLNA/SSDP)
    ufw allow 1900/udp comment 'Plex DLNA/SSDP Discovery'
    ufw allow 32410/udp comment 'Plex GDM Discovery'
    ufw allow 32412/udp comment 'Plex GDM Discovery'
    ufw allow 32413/udp comment 'Plex GDM Discovery'
    ufw allow 32414/udp comment 'Plex GDM Discovery'
    ufw allow 32469/tcp comment 'Plex DLNA Server'

    log "INFO" "Permitiendo Sonarr (puerto 8989)..."
    ufw allow 8989/tcp comment 'Sonarr TV Series Manager'
    log "INFO" "Permitiendo Radarr (puerto 7878)..."
    ufw allow 7878/tcp comment 'Radarr Movie Manager'
    log "INFO" "Permitiendo Lidarr (puerto 8686)..."
    ufw allow 8686/tcp comment 'Lidarr Music Manager'
    log "INFO" "Permitiendo Readarr (puerto 8787)..."
    ufw allow 8787/tcp comment 'Readarr Book Manager'
    log "INFO" "Permitiendo Whisparr (puerto 6969)..." # Puerto común, verifica tu config
    ufw allow 6969/tcp comment 'Whisparr XXX Manager'
    log "INFO" "Permitiendo Bazarr (puerto 6767)..."
    ufw allow 6767/tcp comment 'Bazarr Subtitle Manager'
    log "INFO" "Permitiendo Prowlarr (puerto 9696)..."
    ufw allow 9696/tcp comment 'Prowlarr Indexer Manager'

    # --- Otras aplicaciones mencionadas ---

    # Rclone: Usado para sincronizar/montar, normalmente no abre puertos *a menos que* uses 'rclone serve' (ej. rclone serve webdav :8080).
    #          Si usas 'rclone serve', añade la regla para el puerto específico que configures.
    #          Ejemplo: ufw allow 8080/tcp comment 'Rclone WebDAV service'

    # --- Opcional: Puertos Web estándar (si alojas algo más) ---
    log "INFO" "Permitiendo HTTP (puerto 80)..."
    ufw allow 80/tcp comment 'Standard HTTP'
    log "INFO" "Permitiendo HTTPS (puerto 443)..."
    ufw allow 443/tcp comment 'Standard HTTPS'

    # --- Recargar UFW para aplicar reglas ---
    log "INFO" "Recargando configuración de UFW..."
    if ufw reload; then
        log "INFO" "Reglas de firewall aplicadas correctamente."
    else
        log "WARN" "No se pudo recargar UFW. Puede que las reglas no estén activas."
        return 1 # Devuelve error si no se puede recargar
    fi

    log "INFO" "Verificando estado del firewall:"
    ufw status verbose # Muestra el estado actual detallado

    log "INFO" "Configuración de firewall completada."
    return 0 # Éxito
}

# --- Ejemplo de uso ---
# Asegúrate de definir WEBUI_PORT y CONTROL_PORT antes si no usas los defaults
# export WEBUI_PORT=4711
# export CONTROL_PORT=4712

# Llamar a la función
# configure_firewall

# Comprobar el código de salida (opcional)
# if [ $? -ne 0 ]; then
#    log "ERROR" "La configuración del firewall falló."
# fi

# Configura /etc/default y llama a la generación/configuración de amule.conf
configure_amule() {
    log "INFO" "Iniciando configuración de aMule..."

    # 1. Configurar /etc/default/amule-daemon (variables básicas para el servicio)
    log "INFO" "Configurando /etc/default/amule-daemon..."
    cat > /etc/default/amule-daemon <<EOF
# Configurado por install_amule.sh
# Usuario con el que correrá el daemon
AMULED_USER="${AMULE_USER}"
# Directorio principal para los archivos de configuración (.aMule) y datos
AMULED_HOME="${AMULE_HOME}"
# Esta variable puede ser usada por algunos scripts de inicio antiguos,
# pero systemd usa 'systemctl enable/disable'. La dejamos por compatibilidad.
ENABLE_DAEMON=1
EOF
    log "INFO" "/etc/default/amule-daemon configurado."

    # 2. Generar configuración inicial si no existe
    # amuled crea el directorio .aMule y amule.conf si no existen
    local config_dir="${AMULE_HOME}/.aMule"
    local config_file="${config_dir}/amule.conf"

    if [[ ! -f "$config_file" ]]; then
        generate_initial_config "$config_dir"
    else
        log "INFO" "Archivo de configuración existente encontrado: ${config_file}"
    fi

    # 3. Aplicar configuraciones personalizadas a amule.conf
    # Necesitamos las contraseñas del archivo JSON
    local control_password web_password
    control_password=$(jq -r '.password' "$CREDENTIALS_FILE")
    web_password=$(jq -r '.web_password' "$CREDENTIALS_FILE")

    configure_amule_conf "$config_file" "$control_password" "$web_password"
}


# Genera la configuración inicial ejecutando amuled brevemente en segundo plano
generate_initial_config() {
    local config_dir="$1"
    log "INFO" "Generando configuración inicial de aMule en ${config_dir}..."

    # Crear directorio padre si no existe (seguridad extra)
    mkdir -p "$(dirname "$config_dir")"
    chown "${AMULE_USER}:${AMULE_USER}" "$(dirname "$config_dir")"

    # Ejecutar amuled como el usuario AMULE_USER.
    # Quitar --exit. Ejecutar en segundo plano con '&' para no bloquear el script.
    log "INFO" "Ejecutando amuled en segundo plano para crear ${config_dir}..."
    if sudo -u "${AMULE_USER}" amuled --config-dir="${config_dir}" &> /dev/null & then
        # &> /dev/null redirige stdout y stderr para que no ensucien el log principal
        local amuled_pid=$! # Capturar el PID del proceso en segundo plano
        log "INFO" "amuled iniciado en segundo plano (PID: $amuled_pid). Esperando 5 segundos para la creación de archivos..."
        sleep 5 # Dar tiempo a que los archivos se escriban (ajustar si es necesario)

        # Intentar detener el proceso amuled por PID primero (más seguro)
        log "INFO" "Intentando detener el proceso amuled (PID: $amuled_pid)..."
        if sudo kill "$amuled_pid" &> /dev/null ; then
             log "INFO" "Señal KILL enviada a amuled (PID: $amuled_pid)."
             # Esperar un poco a que termine limpiamente
             wait "$amuled_pid" 2>/dev/null || true
        else
             log "WARN" "No se pudo enviar señal KILL al PID $amuled_pid (¿ya terminó?). Intentando pkill..."
             # Como fallback, usar pkill por usuario si kill falla
             sudo pkill -u "${AMULE_USER}" amuled || true
        fi
        sleep 1 # Pequeña pausa adicional
    else
        # Si amuled falla al iniciar incluso sin --exit
        log "ERROR" "Fallo al ejecutar 'amuled --config-dir=${config_dir}' como ${AMULE_USER} en segundo plano."
        log "ERROR" "Verifica que el usuario y el directorio ${AMULE_HOME} existen y tienen permisos correctos."
        return 1 # Devolver fallo
    fi

    # Verificar que el archivo de configuración se creó después de detener
    if [[ ! -f "${config_dir}/amule.conf" ]]; then
        log "ERROR" "¡El archivo de configuración ${config_dir}/amule.conf no fue creado por amuled!"
        log "ERROR" "Revisa los logs del sistema (journalctl) o intenta ejecutar 'sudo -u ${AMULE_USER} amuled --config-dir=${config_dir}' manualmente para ver errores."
        return 1 # Devolver fallo
    fi
    log "INFO" "Configuración inicial generada en ${config_dir}/amule.conf"
    return 0 # Indicar éxito
}

# Modifica el archivo amule.conf usando sed
configure_amule_conf() {
    local config_file="$1"
    local control_password="$2"
    local web_password="$3"

    log "INFO" "Aplicando configuraciones personalizadas a: ${config_file}"
    [[ -f "$config_file" ]] || { log "ERROR" "Archivo de configuración no encontrado para modificar: $config_file"; exit 1; }

    # Calcular hashes MD5 (aMule los requiere en este formato)
    local ec_password_md5
    local web_password_md5
    ec_password_md5=$(echo -n "$control_password" | md5sum | awk '{print $1}')
    web_password_md5=$(echo -n "$web_password" | md5sum | awk '{print $1}')

    # Usar sed para modificar las líneas. Usamos '|' como delimitador para evitar problemas con '/' en rutas.
    # -i.bak crea un backup del archivo original con extensión .bak
    sed -i.bak \
        -e "s|^AcceptExternalConnections=.*|AcceptExternalConnections=1|" \
        -e "s|^ECPassword=.*|ECPassword=${ec_password_md5}|" \
        -e "s|^UPnPEnabled=.*|UPnPEnabled=0|" `# Deshabilitar UPnP por seguridad/simplicidad` \
        -e "s|^MaxConnections=.*|MaxConnections=500|" `# Ajustar según necesidad` \
        -e "/^\[WebServer\]/,/^\[/ s|^Enabled=.*|Enabled=1|" `# Habilitar WebUI (sección [WebServer])` \
        -e "/^\[WebServer\]/,/^\[/ s|^Password=.*|Password=${web_password_md5}|" `# Establecer pass WebUI` \
        -e "/^\[WebServer\]/,/^\[/ s|^Port=.*|Port=${WEBUI_PORT}|" `# Establecer puerto WebUI` \
        -e "/^\[WebServer\]/,/^\[/ s|^UseSSL=.*|UseSSL=1|" `# Habilitar SSL` \
        -e "s|^SSLCertificateFile=.*|SSLCertificateFile=${SSL_CERT_FILE}|" `# Ruta al certificado` \
        -e "s|^SSLCertificateKeyFile=.*|SSLCertificateKeyFile=${SSL_KEY_FILE}|" `# Ruta a la clave` \
        -e "/^\[WebServer\]/,/^\[/ s|^Template=.*|Template=default|" `# Template WebUI` \
        "$config_file" || {
        log "ERROR" "Fallo al modificar ${config_file} con sed."
        # Restaurar backup si falló? Podría ser útil
        # mv "${config_file}.bak" "$config_file"
        exit 1
    }

    # Eliminar backup si sed tuvo éxito
    rm -f "${config_file}.bak"

    # Asegurar permisos correctos después de modificar
    chown "${AMULE_USER}:${AMULE_USER}" "$config_file" || log "WARN" "No se pudo cambiar propietario de ${config_file}"
    chmod 600 "$config_file" || log "WARN" "No se pudo cambiar permisos de ${config_file}" # Más restrictivo

    log "INFO" "Configuraciones aplicadas correctamente a ${config_file}."
}


enable_services() {
    log "INFO" "Habilitando e iniciando el servicio amule-daemon..."
    systemctl daemon-reload # Asegurar que systemd lee los cambios en /etc/default si los hubiera
    # Habilitar para que inicie en el arranque y iniciar ahora
    systemctl enable --now amule-daemon || {
        log "ERROR" "Fallo al habilitar o iniciar el servicio amule-daemon."
        log "ERROR" "Revisa los logs del servicio con: journalctl -u amule-daemon -n 50 --no-pager"
        exit 1
    }
    log "INFO" "Servicio amule-daemon habilitado e iniciado."
}

final_checks() {
    log "INFO" "Realizando verificaciones finales..."

    # 1. Verificar que el servicio está activo
    if ! systemctl is-active --quiet amule-daemon; then
        log "ERROR" "El servicio amule-daemon no se está ejecutando después de intentar iniciarlo."
        log "ERROR" "Revisa los logs: journalctl -u amule-daemon -n 50 --no-pager"
        exit 1
    fi
    log "INFO" "Servicio amule-daemon está activo."

    # 2. Verificar conexión de control con amulecmd
    log "INFO" "Esperando 5 segundos para que el daemon esté listo..."
    sleep 5

    local control_password ip_address
    control_password=$(jq -r '.password' "$CREDENTIALS_FILE")
    # Obtener IP usando la función de utils.sh
    ip_address=$(get_ip_address || echo "TU_IP_LOCAL") # Fallback si get_ip_address falla

    log "INFO" "Intentando conectar con amulecmd usando la contraseña de control..."
    if ! amulecmd -h localhost -p "${CONTROL_PORT}" -P "$control_password" -c "Status" >/dev/null 2>&1; then
        log "ERROR" "Fallo en la conexión de control con amulecmd."
        log "ERROR" "Posibles causas: Contraseña incorrecta en ${CREDENTIALS_FILE}, daemon no iniciado correctamente, firewall bloqueando puerto ${CONTROL_PORT} en localhost."
        log "ERROR" "Revisa los logs: journalctl -u amule-daemon -n 50 --no-pager"
        exit 1
    fi
    log "INFO" "Conexión de control con amulecmd exitosa."

    # 3. Mensaje final
    log "SUCCESS" "¡Instalación y configuración de aMule completada!"
    log "INFO" "El daemon aMule se está ejecutando como usuario '${AMULE_USER}'."
    log "INFO" "Archivos de configuración y datos en: ${AMULE_HOME}"
    log "INFO" "WebUI (HTTPS) debería estar disponible en: https://${ip_address}:${WEBUI_PORT}"
    log "INFO" "Usa la contraseña web definida en ${CREDENTIALS_FILE} para acceder."
    log "INFO" "Puedes controlar el daemon desde la línea de comandos con: amulecmd -P '${control_password}' -c <comando>"
}

# --- Ejecución Principal ---
# Pasa cualquier argumento recibido al script a la función main
main "$@"