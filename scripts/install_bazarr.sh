#!/bin/bash
### Descripción: Instalación automatizada e idempotente de Bazarr para Raspberry Pi OS
### Versión: 1.1.0 (Añadida solución para TemplateNotFound con enlace simbólico y ajustes systemd)

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Carga de biblioteca de utilidades y configuración inicial
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
UTILS_LIB_PATH="/opt/confiraspa/lib/utils.sh"

if [[ ! -f "$UTILS_LIB_PATH" ]]; then
    echo "[ERROR] [$(basename "$0")] Biblioteca de utilidades no encontrada en '$UTILS_LIB_PATH'. Saliendo." >&2
    exit 1
fi
# shellcheck source=/opt/confiraspa/lib/utils.sh
source "$UTILS_LIB_PATH" || {
    echo "[ERROR] [$(basename "$0")] Fallo al cargar la biblioteca de utilidades '$UTILS_LIB_PATH'. Saliendo." >&2
    exit 1
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Configuración global
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
declare -A CONFIG=(
    [APP_NAME]="bazarr"
    [INSTALL_DIR]="/opt/bazarr"
    [DATA_DIR]="/var/lib/bazarr"
    [SERVICE_FILE]="/etc/systemd/system/bazarr.service"
    [CONFIG_FILE]="/opt/confiraspa/configs/arr_user.json"
    [PORT]="6767"
    [UMASK]="0002"
    # Añadido 'git' explícitamente si no estaba
    [PREREQUISITES]="git libxml2-dev libxslt1-dev python3-libxml2 python3-lxml unrar-free ffmpeg libatlas-base-dev python3-distutils python3-pip python3-venv"
    [REPO_URL]="https://github.com/morpheus65535/bazarr.git"
    # Directorios específicos de Bazarr
    [FRONTEND_DIR]="" # Se define después de INSTALL_DIR
    [TEMPLATES_LINK]="" # Se define después de INSTALL_DIR
    # Rutas VENV
    [VENV_DIR]=""
    [VENV_PYTHON]=""
    [VENV_PIP]=""
)
# Definir rutas dinámicamente
CONFIG[FRONTEND_DIR]="${CONFIG[INSTALL_DIR]}/frontend"
CONFIG[TEMPLATES_LINK]="${CONFIG[INSTALL_DIR]}/templates" # Ubicación deseada del enlace simbólico
CONFIG[VENV_DIR]="${CONFIG[INSTALL_DIR]}/venv"
CONFIG[VENV_PYTHON]="${CONFIG[VENV_DIR]}/bin/python3"
CONFIG[VENV_PIP]="${CONFIG[VENV_DIR]}/bin/pip"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Funciones Principales (Reutilizadas y Nuevas)
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# --- Funciones Reutilizadas (load_user_config, setup_system_user, configure_directories, install_system_dependencies, clone_repo, install_python_requirements, set_permissions, verify_installation) ---
# (Se asume que estas funciones son las mismas que en la versión anterior del script,
#  particularmente `set_permissions` que ya maneja el chown/chmod recursivo)
load_user_config() {
    log "INFO" "Cargando configuración de usuario desde ${CONFIG[CONFIG_FILE]}"
    if [[ ! -f "${CONFIG[CONFIG_FILE]}" ]]; then log "ERROR" "Archivo de config no encontrado: ${CONFIG[CONFIG_FILE]}"; return 1; fi
    local user group
    user=$(jq -re '.user' "${CONFIG[CONFIG_FILE]}") || { log "ERROR" "Fallo al leer 'user' desde JSON (${CONFIG[CONFIG_FILE]})"; return 1; }
    group=$(jq -re '.group' "${CONFIG[CONFIG_FILE]}") || { log "ERROR" "Fallo al leer 'group' desde JSON (${CONFIG[CONFIG_FILE]})"; return 1; }
    if [[ -z "$user" || -z "$group" ]]; then log "ERROR" "Config JSON incompleta ('user'/'group')"; return 1; fi
    CONFIG[SERVICE_USER]="$user"; CONFIG[SERVICE_GROUP]="$group"
    log "INFO" "Usuario/Grupo servicio: '${CONFIG[SERVICE_USER]}'/'${CONFIG[SERVICE_GROUP]}'"
    return 0
}
setup_system_user() {
    log "INFO" "Asegurando usuario/grupo del sistema..."
    if ! getent group "${CONFIG[SERVICE_GROUP]}" >/dev/null; then
        log "INFO" "Creando grupo sistema: ${CONFIG[SERVICE_GROUP]}"
        groupadd --system "${CONFIG[SERVICE_GROUP]}" || { log "ERROR" "Fallo al crear grupo ${CONFIG[SERVICE_GROUP]}"; return 1; }
    else log "DEBUG" "Grupo ${CONFIG[SERVICE_GROUP]} ya existe."; fi
    if ! id -u "${CONFIG[SERVICE_USER]}" >/dev/null 2>&1; then
        log "INFO" "Creando usuario sistema: ${CONFIG[SERVICE_USER]}"
        useradd --system --no-create-home --gid "${CONFIG[SERVICE_GROUP]}" --shell /usr/sbin/nologin "${CONFIG[SERVICE_USER]}" || { log "ERROR" "Fallo al crear usuario ${CONFIG[SERVICE_USER]}"; return 1; }
    else log "DEBUG" "Usuario ${CONFIG[SERVICE_USER]} ya existe."; fi
    if ! groups "${CONFIG[SERVICE_USER]}" | grep -qw "${CONFIG[SERVICE_GROUP]}"; then
         log "INFO" "Añadiendo ${CONFIG[SERVICE_USER]} al grupo ${CONFIG[SERVICE_GROUP]}"
         usermod -a -G "${CONFIG[SERVICE_GROUP]}" "${CONFIG[SERVICE_USER]}" || { log "ERROR" "No se pudo añadir usuario a grupo"; return 1; }
    fi
    return 0
}
configure_directories() {
    log "INFO" "Configurando directorio datos (${CONFIG[DATA_DIR]})..."
    local owner_group="${CONFIG[SERVICE_USER]}:${CONFIG[SERVICE_GROUP]}"
    mkdir -p "${CONFIG[DATA_DIR]}" || { log "ERROR" "No se pudo crear ${CONFIG[DATA_DIR]}"; return 1; }
    chown "$owner_group" "${CONFIG[DATA_DIR]}" || { log "ERROR" "Fallo chown en ${CONFIG[DATA_DIR]}"; return 1; }
    chmod 775 "${CONFIG[DATA_DIR]}" || { log "ERROR" "Fallo chmod en ${CONFIG[DATA_DIR]}"; return 1; }
    log "DEBUG" "Directorio datos configurado: ${CONFIG[DATA_DIR]}"
    return 0
}
install_system_dependencies() {
    log "INFO" "Instalando dependencias del sistema..."
    install_dependencies ${CONFIG[PREREQUISITES]} || return 1
    return 0
}
clone_repo() {
    if [[ -d "${CONFIG[INSTALL_DIR]}/.git" ]]; then
        log "INFO" "Directorio ${CONFIG[INSTALL_DIR]} ya existe. Saltando clonación."
        # Aquí se podría añadir 'git pull' para actualizaciones
        return 0
    fi
    if [[ -d "${CONFIG[INSTALL_DIR]}" ]]; then
        log "WARN" "Directorio ${CONFIG[INSTALL_DIR]} existe pero no es repo git. Eliminar manualmente y reintentar."
        return 1
    fi
     mkdir -p "$(dirname "${CONFIG[INSTALL_DIR]}")" || { log "ERROR" "No se pudo crear directorio padre para ${CONFIG[INSTALL_DIR]}"; return 1; }
    log "INFO" "Clonando Bazarr desde ${CONFIG[REPO_URL]} a ${CONFIG[INSTALL_DIR]}..."
    git clone --depth 1 "${CONFIG[REPO_URL]}" "${CONFIG[INSTALL_DIR]}" || { log "ERROR" "Fallo al clonar repo"; rm -rf "${CONFIG[INSTALL_DIR]}"; return 1; }
    log "INFO" "Repositorio clonado."
    return 0
}
install_python_requirements() {
    local req_file="${CONFIG[INSTALL_DIR]}/requirements.txt"
    if [[ ! -f "$req_file" ]]; then log "ERROR" "requirements.txt no encontrado en ${CONFIG[INSTALL_DIR]}"; return 1; fi
    log "INFO" "Configurando venv en ${CONFIG[VENV_DIR]}"
    if [[ ! -d "${CONFIG[VENV_DIR]}" ]]; then
        python3 -m venv "${CONFIG[VENV_DIR]}" || { log "ERROR" "Fallo al crear venv"; return 1; }
        log "INFO" "Venv creado."
        chown -R "${CONFIG[SERVICE_USER]}:${CONFIG[SERVICE_GROUP]}" "${CONFIG[VENV_DIR]}" || log "WARN" "Fallo chown inicial venv."
    else log "DEBUG" "Venv ya existe."; fi
    log "INFO" "Actualizando pip/setuptools/wheel en venv..."
    "${CONFIG[VENV_PIP]}" install --upgrade pip setuptools wheel >/dev/null 2>&1 || log "WARN" "Fallo al actualizar pip/setuptools/wheel."
    log "INFO" "Instalando dependencias Python desde $req_file en venv..."
    "${CONFIG[VENV_PIP]}" install --no-cache-dir -r "$req_file" || { log "ERROR" "Fallo pip install -r $req_file"; return 1; }
    log "SUCCESS" "Dependencias Python instaladas en venv."
    return 0
}
set_permissions() {
    log "INFO" "Estableciendo propietario/permisos en ${CONFIG[INSTALL_DIR]}..."
    local owner_group="${CONFIG[SERVICE_USER]}:${CONFIG[SERVICE_GROUP]}"
    chown -R "$owner_group" "${CONFIG[INSTALL_DIR]}" || { log "ERROR" "Fallo chown -R en ${CONFIG[INSTALL_DIR]}"; return 1; }
    find "${CONFIG[INSTALL_DIR]}" -type d -exec chmod 775 {} \; || { log "ERROR" "Fallo chmod directorios"; return 1; }
    find "${CONFIG[INSTALL_DIR]}" -type f -exec chmod 664 {} \; || { log "ERROR" "Fallo chmod archivos"; return 1; }
    # Asegurar ejecución en binarios venv y script principal si existe
    [[ -d "${CONFIG[VENV_DIR]}/bin" ]] && chmod -R ug+x "${CONFIG[VENV_DIR]}/bin/"
    # El script principal ahora se ejecuta con -m, así que no necesita +x directamente
    # [[ -f "${CONFIG[INSTALL_DIR]}/bazarr.py" ]] && chmod ug+x "${CONFIG[INSTALL_DIR]}/bazarr.py"
    log "INFO" "Permisos establecidos."
    return 0
}
verify_installation() {
    log "INFO" "Verificando estado servicio ${CONFIG[APP_NAME]}..."
    sleep 5
    if ! systemctl is-active --quiet "${CONFIG[APP_NAME]}.service"; then
        log "ERROR" "Servicio ${CONFIG[APP_NAME]} no está activo."
        systemctl status "${CONFIG[APP_NAME]}.service" --no-pager -n 50
        journalctl -u "${CONFIG[APP_NAME]}" -n 50 --no-pager
        return 1
    fi
    log "INFO" "Servicio ${CONFIG[APP_NAME]} activo."
    local local_url="http://127.0.0.1:${CONFIG[PORT]}"
    log "INFO" "Intentando conectar a ${local_url}..."
    if ! curl --fail --silent --max-time 15 "$local_url" > /dev/null; then
         log "INFO" "Primer intento fallido, esperando 10s y reintentando..."
         sleep 10
         if ! curl --fail --silent --max-time 10 "$local_url" > /dev/null; then
             log "WARN" "No se pudo conectar a $local_url tras reintento."
         else log "INFO" "Conexión local a $local_url exitosa tras reintento."; fi
    else log "INFO" "Conexión local a $local_url exitosa."; fi
    local ip_address
    ip_address=$(get_ip_address) || ip_address="<IP no detectada>"
    log "SUCCESS" "Instalación/Configuración de ${CONFIG[APP_NAME]} completada."
    log "INFO" "Acceso web: http://${ip_address}:${CONFIG[PORT]}"
    log "INFO" "Usuario/Grupo: ${CONFIG[SERVICE_USER]}/${CONFIG[SERVICE_GROUP]}"
    log "INFO" "Directorio instalación: ${CONFIG[INSTALL_DIR]}"
    log "INFO" "Directorio datos: ${CONFIG[DATA_DIR]}"
    return 0
}
# --- FIN Funciones Reutilizadas ---

#--- Crear enlace simbólico para plantillas (Solución TemplateNotFound) ---
create_template_symlink() {
    log "INFO" "Creando enlace simbólico para plantillas (solución TemplateNotFound)..."
    local frontend_dir="${CONFIG[FRONTEND_DIR]}"
    local template_link="${CONFIG[TEMPLATES_LINK]}"

    # Verificar que el directorio frontend existe
    if [[ ! -d "$frontend_dir" ]]; then
        log "ERROR" "El directorio frontend (${frontend_dir}) no existe. No se puede crear el enlace."
        return 1
    fi

    # Verificar si el enlace ya existe y apunta al lugar correcto
    if [[ -L "$template_link" ]]; then
        local current_target
        current_target=$(readlink "$template_link")
        if [[ "$current_target" == "$frontend_dir" ]]; then
            log "DEBUG" "Enlace simbólico '${template_link}' ya existe y apunta correctamente."
            return 0
        else
            log "WARN" "Enlace simbólico '${template_link}' existe pero apunta a '${current_target}'. Se eliminará y recreará."
            if ! rm "$template_link"; then
                log "ERROR" "No se pudo eliminar el enlace simbólico existente '${template_link}'."
                return 1
            fi
        fi
    # Verificar si existe un archivo/directorio normal con ese nombre (conflicto)
    elif [[ -e "$template_link" ]]; then
         log "ERROR" "Ya existe un archivo o directorio normal en '${template_link}'. No se puede crear el enlace."
         return 1
    fi

    # Crear el enlace simbólico
    log "INFO" "Creando enlace: ${template_link} -> ${frontend_dir}"
    # ln -s TARGET LINK_NAME
    if ! ln -s "$frontend_dir" "$template_link"; then
        log "ERROR" "Fallo al crear el enlace simbólico '${template_link}'."
        return 1
    fi

    # Asegurar que el propietario del enlace sea correcto (aunque a menudo no importa para symlinks)
    # Usar -h para cambiar el propietario del enlace en sí, no del objetivo
    chown -h "${CONFIG[SERVICE_USER]}:${CONFIG[SERVICE_GROUP]}" "$template_link" || log "WARN" "No se pudo establecer propietario del enlace simbólico ${template_link}"

    log "INFO" "Enlace simbólico para plantillas creado/verificado."
    return 0
}


#--- Configuración del Servicio Systemd (Aplicando solución TemplateNotFound) ---
configure_service() {
    log "INFO" "Configurando servicio systemd para ${CONFIG[APP_NAME]} (con ajustes para TemplateNotFound)..."

    # Usar create_backup de utils.sh
    create_backup "${CONFIG[SERVICE_FILE]}" || log "WARN" "No se pudo crear backup de ${CONFIG[SERVICE_FILE]}."

    # Definir cómo ejecutar Bazarr: como módulo (-m)
    # Usar python del venv
    local exec_start="${CONFIG[VENV_PYTHON]} -m bazarr --no-update --config=${CONFIG[DATA_DIR]}"

    # Crear el archivo de servicio
    cat > "${CONFIG[SERVICE_FILE]}" <<EOF
[Unit]
Description=Bazarr Daemon (Managed by Confiraspa)
After=syslog.target network-online.target
Wants=network-online.target

[Service]
# Añadir PYTHONPATH puede ayudar a encontrar módulos internos
Environment="PYTHONPATH=${CONFIG[INSTALL_DIR]}"

# Reintentar con WorkingDirectory, ya que es más limpio si funciona
WorkingDirectory=${CONFIG[INSTALL_DIR]}

User=${CONFIG[SERVICE_USER]}
Group=${CONFIG[SERVICE_GROUP]}
UMask=${CONFIG[UMASK]}
Type=simple

# Ejecutar como módulo
ExecStart=${exec_start}

Restart=on-failure
RestartSec=5
TimeoutStopSec=20
KillSignal=SIGINT
SyslogIdentifier=${CONFIG[APP_NAME]}

[Install]
WantedBy=multi-user.target
EOF

    # Verificar creación y permisos
    if [[ ! -f "${CONFIG[SERVICE_FILE]}" ]]; then log "ERROR" "Fallo al crear ${CONFIG[SERVICE_FILE]}"; return 1; fi
    chmod 644 "${CONFIG[SERVICE_FILE]}"

    log "INFO" "Recargando systemd (daemon-reload)..."
    systemctl daemon-reload || { log "ERROR" "Fallo systemctl daemon-reload."; return 1; }

    log "INFO" "Habilitando e iniciando servicio ${CONFIG[APP_NAME]} (enable --now)..."
    if ! systemctl enable --now "${CONFIG[APP_NAME]}.service"; then
        log "ERROR" "Fallo al habilitar/iniciar servicio ${CONFIG[APP_NAME]}."
        journalctl -u "${CONFIG[APP_NAME]}" -n 20 --no-pager
        # Si falla aquí, podría ser el error CHDIR de nuevo.
        # Considerar volver al workaround `bash -c 'cd...'` si WorkingDirectory sigue fallando.
        return 1
    fi

    log "INFO" "Servicio ${CONFIG[APP_NAME]} configurado, habilitado e iniciado."
    return 0
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Flujo Principal del Script (main)
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
main() {
    setup_error_handling
    log "INFO" "== Iniciando script instalación/configuración de ${CONFIG[APP_NAME]} v1.1.0 =="

    check_root || exit 1
    check_network_connectivity

    load_user_config || exit 1
    setup_system_user || exit 1
    configure_directories || exit 1 # Crear DATA_DIR

    install_system_dependencies || exit 1

    clone_repo || exit 1                  # Clonar código fuente
    install_python_requirements || exit 1 # Instalar dependencias Python en venv
    set_permissions || exit 1             # Establecer permisos generales

    # PASO CLAVE: Crear enlace simbólico para solucionar TemplateNotFound
    create_template_symlink || exit 1

    # Configurar y arrancar el servicio (con los nuevos ajustes)
    configure_service || exit 1

    # Verificación final
    verify_installation || exit 1

    log "INFO" "== Script de ${CONFIG[APP_NAME]} finalizado con éxito =="
    exit 0
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Ejecución
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
main "$@"