#!/bin/bash
# Script refactorizado para instalar y configurar Calibre Content Server en Raspberry Pi OS
# Utiliza el usuario y grupo definidos en arr_user.json
# Versión: calibre-1.2.0
# Uso: sudo ./install_calibre_shared_user.sh
set -euo pipefail
# --- Configuración inicial y Carga de Biblioteca ---
SCRIPT_NAME=$(basename "$0" .sh)
export LOG_FILE # Será definido por setup_paths()

UTILS_PATH="/opt/confiraspa/lib/utils.sh"
if [[ ! -f "$UTILS_PATH" || ! -r "$UTILS_PATH" ]]; then
    echo "[$(date --iso-8601=seconds)] [CRITICAL] [${SCRIPT_NAME}] Biblioteca de utilidades no encontrada o ilegible en: $UTILS_PATH" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$UTILS_PATH" || {
    echo "[$(date --iso-8601=seconds)] [CRITICAL] [${SCRIPT_NAME}] Error al cargar la biblioteca de utilidades: $UTILS_PATH" >&2
    exit 1
}

# --- Constantes y Configuración Específica ---
[[ -z "$CONFIG_DIR" ]] && { log "CRITICAL" "CONFIG_DIR no definido por utils.sh"; exit 1; }

readonly CALIBRE_CONFIG_FILE="${CONFIG_DIR}/calibre_config.json"
readonly USER_CONFIG_FILE="${CONFIG_DIR}/arr_user.json" # Archivo con usuario/grupo
readonly CALIBRE_INSTALLER_URL="https://download.calibre-ebook.com/linux-installer.sh"
readonly CALIBRE_INSTALLER_PATH="/tmp/calibre-installer.sh"
readonly CALIBRE_INSTALL_DIR="/opt/calibre"
readonly CALIBRE_BIN_DIR="${CALIBRE_INSTALL_DIR}/calibre" # <--- NUEVA LÍNEA
readonly SYSTEMD_SERVICE_NAME="calibre-server.service"
readonly SYSTEMD_DIR="/etc/systemd/system"
readonly SYSTEMD_SERVICE_FILE="${SYSTEMD_DIR}/${SYSTEMD_SERVICE_NAME}"

# Variables globales para la configuración (se llenarán en las funciones de parseo)
declare CALIBRE_LIBRARY_PATH=""
declare TARGET_USER=""
declare TARGET_GROUP=""

# --- Funciones Modulares ---

# Parsea y valida la configuración de Calibre (ruta biblioteca)
parse_and_validate_calibre_config() {
    log "INFO" "Parseando y validando archivo de configuración de Calibre: $CALIBRE_CONFIG_FILE"
    if [[ ! -f "$CALIBRE_CONFIG_FILE" ]]; then
        log "ERROR" "Archivo de configuración de Calibre no encontrado: $CALIBRE_CONFIG_FILE"
        return 1
    fi
    if ! CALIBRE_LIBRARY_PATH=$(jq -er '.library_path' "$CALIBRE_CONFIG_FILE"); then
        log "ERROR" "Error al parsear 'library_path' desde $CALIBRE_CONFIG_FILE o la clave no existe/es nula."
        return 1
    fi
    if [[ -z "$CALIBRE_LIBRARY_PATH" ]]; then
        log "ERROR" "'library_path' no puede estar vacío en $CALIBRE_CONFIG_FILE."
        return 1
    fi
    log "INFO" "Ruta de la biblioteca configurada: ${CALIBRE_LIBRARY_PATH}"
    return 0
}

# Parsea y valida la configuración de usuario/grupo desde arr_user.json
# Verifica que el usuario y grupo existan en el sistema.
parse_and_validate_user_config() {
    log "INFO" "Parseando y validando archivo de configuración de usuario: $USER_CONFIG_FILE"
    if [[ ! -f "$USER_CONFIG_FILE" ]]; then
        log "ERROR" "Archivo de configuración de usuario no encontrado: $USER_CONFIG_FILE"
        return 1
    fi

    local user_val group_val
    if ! user_val=$(jq -er '.user' "$USER_CONFIG_FILE"); then
        log "ERROR" "Error al parsear 'user' desde $USER_CONFIG_FILE o la clave no existe/es nula."
        return 1
    fi
     if ! group_val=$(jq -er '.group' "$USER_CONFIG_FILE"); then
        log "ERROR" "Error al parsear 'group' desde $USER_CONFIG_FILE o la clave no existe/es nula."
        return 1
    fi

    if [[ -z "$user_val" || -z "$group_val" ]]; then
        log "ERROR" "'user' o 'group' no pueden estar vacíos en $USER_CONFIG_FILE."
        return 1
    fi

    # Verificar existencia del usuario y grupo en el sistema
    if ! id "$user_val" &>/dev/null; then
        log "ERROR" "El usuario '$user_val' definido en $USER_CONFIG_FILE no existe en el sistema."
        return 1
    fi
     if ! getent group "$group_val" &>/dev/null; then
        log "ERROR" "El grupo '$group_val' definido en $USER_CONFIG_FILE no existe en el sistema."
        return 1
    fi

    TARGET_USER="$user_val"
    TARGET_GROUP="$group_val"
    log "INFO" "Usuario objetivo: ${TARGET_USER}, Grupo objetivo: ${TARGET_GROUP}"
    return 0
}


# Asegura que el directorio de la biblioteca exista.
# Los permisos finales se establecen después.
ensure_library_directory_exists() {
    # Usa la variable global CALIBRE_LIBRARY_PATH
    log "INFO" "Asegurando existencia del directorio de la biblioteca: ${CALIBRE_LIBRARY_PATH}"
    if [[ -z "$CALIBRE_LIBRARY_PATH" ]]; then
         log "ERROR" "Ruta de biblioteca no definida (error interno)."
         return 1
    fi
    if [[ -d "$CALIBRE_LIBRARY_PATH" ]]; then
        log "INFO" "El directorio de la biblioteca ya existe: ${CALIBRE_LIBRARY_PATH}"
        return 0
    else
        log "INFO" "Creando directorio de la biblioteca: ${CALIBRE_LIBRARY_PATH}"
        if ! mkdir -p "$CALIBRE_LIBRARY_PATH"; then
            log "ERROR" "Fallo al crear el directorio: ${CALIBRE_LIBRARY_PATH}. Verifica permisos del padre."
            return 1
        else
            log "INFO" "Directorio creado exitosamente."
            chmod 775 "$CALIBRE_LIBRARY_PATH" || log "WARN" "No se pudieron establecer permisos iniciales 775 en ${CALIBRE_LIBRARY_PATH}"
            return 0
        fi
    fi
}

# Instala Calibre usando el script oficial si no está instalado. (Sin cambios respecto a la versión anterior)
install_calibre_binary() {
    log "INFO" "Verificando instalación de Calibre..."
    # Comprobar si el binario principal existe en la ruta de instalación esperada
    if [[ -x "${CALIBRE_BIN_DIR}/calibre" && -x "${CALIBRE_BIN_DIR}/calibre-server" ]]; then
        # Intentar obtener versión si es posible
        local version_info
        version_info=$("${CALIBRE_BIN_DIR}/calibre" --version 2>/dev/null || echo "(versión desconocida)")
        log "INFO" "Calibre ya parece estar instalado en ${CALIBRE_BIN_DIR}. ${version_info}" # Ajustar log
        return 0
    fi
log "INFO" "Calibre no encontrado en ${CALIBRE_BIN_DIR}. Iniciando instalación..." # Ajustar log
    log "INFO" "Calibre no encontrado en ${CALIBRE_INSTALL_DIR}. Iniciando instalación..."
    check_network_connectivity "download.calibre-ebook.com" || return 1
    log "INFO" "Descargando instalador oficial de Calibre desde ${CALIBRE_INSTALLER_URL}"
    if ! download_secure "$CALIBRE_INSTALLER_URL" "$CALIBRE_INSTALLER_PATH"; then
        log "ERROR" "Fallo al descargar el instalador de Calibre."
        rm -f "$CALIBRE_INSTALLER_PATH"; return 1
    fi
    log "INFO" "Ejecutando instalador de Calibre (esto puede tardar)... Instalando en: ${CALIBRE_INSTALL_DIR}"
    if ! sudo bash "$CALIBRE_INSTALLER_PATH" install_dir="${CALIBRE_INSTALL_DIR}" > >(tee -a "$LOG_FILE") 2>&1; then
        log "ERROR" "Fallo durante la ejecución del instalador de Calibre. Revisa $LOG_FILE y /tmp/calibre-installer-log.txt si existe."
        rm -f "$CALIBRE_INSTALLER_PATH"; return 1
    fi
    rm -f "$CALIBRE_INSTALLER_PATH"
    # Verificar que los comandos esenciales existen después de la instalación
    if [[ ! -x "${CALIBRE_BIN_DIR}/calibre-server" ]]; then
        log "ERROR" "La instalación de Calibre parece haber fallado (no se encontró ${CALIBRE_BIN_DIR}/calibre-server)." # Usar CALIBRE_BIN_DIR
        return 1
    fi
    # Crear enlaces simbólicos en /usr/local/bin para acceso global si se desea
    ln -sf "${CALIBRE_BIN_DIR}/calibre" /usr/local/bin/calibre
    ln -sf "${CALIBRE_BIN_DIR}/calibre-server" /usr/local/bin/calibre-server
    ln -sf "${CALIBRE_BIN_DIR}/ebook-convert" /usr/local/bin/ebook-convert
    # Añade los demás si los necesitas (ebook-device, ebook-meta, etc.)
    log "INFO" "Enlaces simbólicos creados en /usr/local/bin."
}

# Establece la propiedad y permisos correctos en el directorio de la biblioteca
# Usando el usuario y grupo leídos desde la configuración.
set_library_ownership_permissions() {
    # Usa variables globales CALIBRE_LIBRARY_PATH, TARGET_USER, TARGET_GROUP
    log "INFO" "Estableciendo propiedad (${TARGET_USER}:${TARGET_GROUP}) y permisos en: ${CALIBRE_LIBRARY_PATH}"
     if [[ ! -d "$CALIBRE_LIBRARY_PATH" ]]; then
        log "ERROR" "El directorio de la biblioteca no existe (${CALIBRE_LIBRARY_PATH}) al intentar establecer permisos."
        return 1
     fi
    # Cambiar propietario recursivamente
    if ! chown -R "${TARGET_USER}:${TARGET_GROUP}" "$CALIBRE_LIBRARY_PATH"; then
        log "ERROR" "Fallo al cambiar la propiedad de: ${CALIBRE_LIBRARY_PATH} a ${TARGET_USER}:${TARGET_GROUP}"
        log "ERROR" "Verifica que este script (sudo) tenga permisos para cambiar la propiedad a ese usuario/grupo."
        return 1
    fi
    # Establecer permisos (775 directorios / 664 archivos)
    log "INFO" "Aplicando permisos recursivos (directorios 775, archivos 664)..."
    if ! find "$CALIBRE_LIBRARY_PATH" -type d -exec chmod 775 {} +; then
         log "ERROR" "Fallo al establecer permisos 775 en directorios dentro de ${CALIBRE_LIBRARY_PATH}"
         return 1
    fi
     if ! find "$CALIBRE_LIBRARY_PATH" -type f -exec chmod 664 {} +; then
         log "ERROR" "Fallo al establecer permisos 664 en archivos dentro de ${CALIBRE_LIBRARY_PATH}"
         return 1
    fi
    log "SUCCESS" "Propiedad y permisos establecidos correctamente para ${CALIBRE_LIBRARY_PATH} (${TARGET_USER}:${TARGET_GROUP})."
    return 0
}


# Configura y habilita el servicio systemd para calibre-server.
# Usando el usuario y grupo leídos desde la configuración.
configure_and_start_systemd_service() {
    # Usa variables globales CALIBRE_LIBRARY_PATH, TARGET_USER, TARGET_GROUP
    log "INFO" "Configurando y habilitando el servicio systemd: ${SYSTEMD_SERVICE_NAME}"
    create_backup "$SYSTEMD_SERVICE_FILE"

    # Generar contenido del archivo de servicio
    local service_content
    read -r -d '' service_content <<EOF
[Unit]
Description=Calibre Content Server (Usuario: ${TARGET_USER})
After=network.target $(systemd-escape -p --suffix=mount "${CALIBRE_LIBRARY_PATH}")
Requires=network.target $(systemd-escape -p --suffix=mount "${CALIBRE_LIBRARY_PATH}")

[Service]
Type=simple
User=${TARGET_USER}
Group=${TARGET_GROUP}
ExecStart=${CALIBRE_BIN_DIR}/calibre-server --port=8080 --enable-local-write "${CALIBRE_LIBRARY_PATH}"
Restart=on-failure
RestartSec=5s
# Opcional: Añadir límites de recursos si se desea
# MemoryAccounting=yes
# MemoryMax=512M

[Install]
WantedBy=multi-user.target
EOF

    log "INFO" "Creando/Actualizando archivo de servicio: ${SYSTEMD_SERVICE_FILE}"
    if ! echo "$service_content" > "$SYSTEMD_SERVICE_FILE"; then
        log "ERROR" "Fallo al escribir el archivo de servicio: ${SYSTEMD_SERVICE_FILE}"; restore_backup "$SYSTEMD_SERVICE_FILE"; return 1
    fi
    if ! chmod 644 "$SYSTEMD_SERVICE_FILE"; then
        log "WARN" "No se pudieron establecer permisos 644 en ${SYSTEMD_SERVICE_FILE}"
    fi

    log "INFO" "Recargando configuración de systemd (daemon-reload)..."
    if ! systemctl daemon-reload; then
        log "ERROR" "Fallo al ejecutar systemctl daemon-reload."; return 1
    fi

    log "INFO" "Habilitando e iniciando el servicio ${SYSTEMD_SERVICE_NAME}..."
    if ! systemctl enable --now "$SYSTEMD_SERVICE_NAME"; then
        log "ERROR" "Fallo al habilitar o iniciar el servicio ${SYSTEMD_SERVICE_NAME}."; log "INFO" "Logs:"; journalctl -u "$SYSTEMD_SERVICE_NAME" -n 20 --no-pager; return 1
    fi

    sleep 2
    if ! systemctl is-active --quiet "$SYSTEMD_SERVICE_NAME"; then
         log "ERROR" "El servicio ${SYSTEMD_SERVICE_NAME} se habilitó pero no está activo."; journalctl -u "$SYSTEMD_SERVICE_NAME" -n 20 --no-pager; return 1
    fi
     if ! systemctl is-enabled --quiet "$SYSTEMD_SERVICE_NAME"; then
         log "WARN" "El servicio ${SYSTEMD_SERVICE_NAME} está activo pero no habilitado para iniciar en el arranque."
    fi

    log "SUCCESS" "Servicio systemd ${SYSTEMD_SERVICE_NAME} configurado, habilitado e iniciado correctamente (Usuario: ${TARGET_USER})."
    return 0
}

# --- Función Principal de Orquestación ---
main() {
    setup_error_handling
    if ! setup_paths; then echo "[$(date --iso-8601=seconds)] [CRITICAL] [${SCRIPT_NAME}] Fallo setup_paths. Abortando." >&2; exit 1; fi
    check_root
    log "INFO" "--- Iniciando Instalación/Configuración de Calibre Server (Usuario Configurado) ---"

    # 1. Dependencias
    if ! install_dependencies "jq" "curl" "libxcb-cursor0"; then log "ERROR" "Fallo al instalar dependencias. Abortando."; exit 1; fi

    # 2. Parsear configuraciones (Calibre y Usuario)
    if ! parse_and_validate_calibre_config; then log "ERROR" "Configuración Calibre inválida. Abortando."; exit 1; fi
    if ! parse_and_validate_user_config; then log "ERROR" "Configuración Usuario inválida o usuario/grupo no existe. Abortando."; exit 1; fi
    # $CALIBRE_LIBRARY_PATH, $TARGET_USER, $TARGET_GROUP ahora disponibles

    # 3. Asegurar directorio biblioteca
    if ! ensure_library_directory_exists; then log "ERROR" "Fallo directorio biblioteca. Abortando."; exit 1; fi

    # 4. Instalar binario Calibre
    if ! install_calibre_binary; then log "ERROR" "Fallo instalación Calibre. Abortando."; exit 1; fi

    # 5. Establecer permisos finales en biblioteca (¡Importante!)
    # Se ejecuta ANTES de iniciar el servicio que usará el directorio
    if ! set_library_ownership_permissions; then log "ERROR" "Fallo permisos biblioteca. Abortando."; exit 1; fi

    # 6. Configurar e iniciar servicio systemd
    if ! configure_and_start_systemd_service; then
        log "ERROR" "Fallo servicio systemd. La instalación base está OK, pero el servidor NO se inició."
        exit 1 # Salir con error si el servicio es crucial
    fi

    # 7. Éxito
    log "SUCCESS" "--- Instalación/Configuración Calibre Server (Usuario: ${TARGET_USER}) completada ---"
    local ip_address; ip_address=$(get_ip_address)
    echo -e "\n-----------------------------------------------------"
    echo -e " Accede al Calibre Content Server en:"
    echo -e "   \e[1;32mhttp://${ip_address}:8080\e[0m"
    echo -e "-----------------------------------------------------"
    echo -e "\n Servicio gestionado por systemd (ejecutando como ${TARGET_USER}):"
    echo -e "   - Estado: \e[0;33msystemctl status ${SYSTEMD_SERVICE_NAME}\e[0m"
    echo -e "   - Parar:  \e[0;33msystemctl stop ${SYSTEMD_SERVICE_NAME}\e[0m"
    echo -e "   - Iniciar:\e[0;33msystemctl start ${SYSTEMD_SERVICE_NAME}\e[0m"
    echo -e "   - Logs:   \e[0;33mjournalctl -u ${SYSTEMD_SERVICE_NAME} -f\e[0m"
    echo -e "-----------------------------------------------------\n"
    exit 0
}

# --- Punto de Entrada ---
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi