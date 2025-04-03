#!/bin/bash
### Descripción: Instalación automatizada e idempotente de Sonarr para Raspberry Pi OS
### Versión: 2.1.0 (Mejoras en idempotencia, extracción y verificación)

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Carga de biblioteca de utilidades y configuración inicial
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Determinar la ubicación de utils.sh de forma robusta
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
UTILS_LIB_PATH="/opt/confiraspa/lib/utils.sh" # O usa una ruta relativa/descubierta si prefieres

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
# Configuración global (Manteniendo la estructura original)
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
declare -A CONFIG=(
    [APP_NAME]="sonarr"
    [INSTALL_DIR]="/opt/sonarr"             # Directorio de instalación de binarios/ejecutables
    [DATA_DIR]="/var/lib/sonarr"            # Directorio de datos (config.xml, logs, db, etc.)
    [SERVICE_FILE]="/etc/systemd/system/sonarr.service"
    [CONFIG_FILE]="/opt/confiraspa/configs/arr_user.json" # Archivo JSON con user/group
    [PORT]="8989"
    [UMASK]="0002"                          # Permisos por defecto (rw-rw-r--)
    # Añadido jq como prerrequisito
    [PREREQUISITES]="curl sqlite3 wget jq"
    [ARCH_MAP]="amd64:x64 armhf:arm arm64:arm64" # Mapeo arch de dpkg a Sonarr
    # Nota: La versión 4 de Sonarr requiere .NET 6 o superior. Asegúrate de que esté instalado
    # o añade lógica para instalarlo si es necesario (más complejo).
    # Podrías añadir dotnet-sdk-6.0 o similar a PREREQUISITES si tu OS lo empaqueta.
    [RELEASE_URL]="https://services.sonarr.tv/v1/download/main/latest?version=4&os=linux"
    # Nombre esperado del ejecutable principal dentro de INSTALL_DIR
    [EXECUTABLE_NAME]="Sonarr"
)

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Funciones Principales (Refinadas)
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#--- Carga de Configuración de Usuario ---
load_user_config() {
    log "INFO" "Cargando configuración de usuario desde ${CONFIG[CONFIG_FILE]}"

    if [[ ! -f "${CONFIG[CONFIG_FILE]}" ]]; then
        log "ERROR" "Archivo de configuración de usuario no encontrado: ${CONFIG[CONFIG_FILE]}"
        return 1 # Usar return en lugar de exit para permitir manejo de errores más granular si es necesario
    fi

    # Usar jq para extraer valores, con manejo de errores si falla jq o el archivo es inválido
    local user group
    user=$(jq -re '.user' "${CONFIG[CONFIG_FILE]}") || { log "ERROR" "Fallo al leer 'user' desde JSON (${CONFIG[CONFIG_FILE]}) o valor inválido."; return 1; }
    group=$(jq -re '.group' "${CONFIG[CONFIG_FILE]}") || { log "ERROR" "Fallo al leer 'group' desde JSON (${CONFIG[CONFIG_FILE]}) o valor inválido."; return 1; }

    if [[ -z "$user" || -z "$group" ]]; then
        log "ERROR" "Configuración incompleta en JSON. Se requieren 'user' y 'group' no vacíos."
        return 1
    fi

    # Guardar en el array CONFIG si la lectura fue exitosa
    CONFIG[SERVICE_USER]="$user"
    CONFIG[SERVICE_GROUP]="$group"
    log "INFO" "Usuario de servicio configurado como '${CONFIG[SERVICE_USER]}' (Grupo: '${CONFIG[SERVICE_GROUP]}')"
    return 0
}

#--- Configuración de Usuario/Grupo del Sistema (Idempotente) ---
setup_system_user() {
    log "INFO" "Asegurando existencia del usuario y grupo del sistema..."

    # Crear grupo si no existe (Idempotente)
    if ! getent group "${CONFIG[SERVICE_GROUP]}" >/dev/null; then
        log "INFO" "El grupo '${CONFIG[SERVICE_GROUP]}' no existe. Creándolo..."
        if ! groupadd --system "${CONFIG[SERVICE_GROUP]}"; then
            log "ERROR" "Fallo al crear el grupo del sistema '${CONFIG[SERVICE_GROUP]}'."
            return 1
        fi
        log "INFO" "Grupo '${CONFIG[SERVICE_GROUP]}' creado."
    else
        log "DEBUG" "El grupo '${CONFIG[SERVICE_GROUP]}' ya existe."
    fi

    # Crear usuario si no existe (Idempotente)
    if ! id -u "${CONFIG[SERVICE_USER]}" >/dev/null 2>&1; then
        log "INFO" "El usuario '${CONFIG[SERVICE_USER]}' no existe. Creándolo..."
        if ! useradd --system --no-create-home \
                --gid "${CONFIG[SERVICE_GROUP]}" \
                --shell /usr/sbin/nologin \
                "${CONFIG[SERVICE_USER]}"; then
            log "ERROR" "Fallo al crear el usuario del sistema '${CONFIG[SERVICE_USER]}'."
            return 1
        fi
        log "INFO" "Usuario '${CONFIG[SERVICE_USER]}' creado y añadido al grupo '${CONFIG[SERVICE_GROUP]}'."
    else
        log "DEBUG" "El usuario '${CONFIG[SERVICE_USER]}' ya existe."
        # Verificar/Asegurar pertenencia al grupo primario/suplementario si el usuario ya existía
        if ! groups "${CONFIG[SERVICE_USER]}" | grep -qw "${CONFIG[SERVICE_GROUP]}"; then
             log "INFO" "Añadiendo usuario '${CONFIG[SERVICE_USER]}' al grupo '${CONFIG[SERVICE_GROUP]}' (suplementario)."
             usermod -a -G "${CONFIG[SERVICE_GROUP]}" "${CONFIG[SERVICE_USER]}" || {
                 log "ERROR" "No se pudo añadir el usuario existente '${CONFIG[SERVICE_USER]}' al grupo '${CONFIG[SERVICE_GROUP]}'."
                 return 1
             }
        else
             log "DEBUG" "Usuario '${CONFIG[SERVICE_USER]}' ya pertenece al grupo '${CONFIG[SERVICE_GROUP]}'."
        fi
    fi

    return 0
}

#--- Configuración de Directorios (Idempotente) ---
configure_directories() {
    log "INFO" "Configurando directorios y permisos..."
    local dirs=("${CONFIG[INSTALL_DIR]}" "${CONFIG[DATA_DIR]}")
    local dir
    local owner_group="${CONFIG[SERVICE_USER]}:${CONFIG[SERVICE_GROUP]}"

    for dir in "${dirs[@]}"; do
        # Crear directorio (idempotente)
        if ! mkdir -p "$dir"; then
            log "ERROR" "No se pudo crear o acceder al directorio: $dir (Verifica permisos padres)"
            return 1
        fi

        # Establecer propietario/grupo (idempotente en efecto, aunque se ejecuta siempre)
        # Usar -R sólo si es estrictamente necesario y el directorio ya contiene algo que deba heredar.
        # Para el directorio base, -R no es necesario inicialmente.
        if ! chown "$owner_group" "$dir"; then
             log "ERROR" "No se pudo establecer propietario/grupo '$owner_group' en: $dir"
             return 1
        fi

        # Establecer permisos (idempotente en efecto)
        # 775 permite al grupo escribir, útil para DATA_DIR. Para INSTALL_DIR, 755 podría ser suficiente,
        # pero 775 es coherente con el script original y permite actualizaciones/plugins si Sonarr lo necesita.
        if ! chmod 775 "$dir"; then
             log "ERROR" "No se pudieron establecer permisos 775 en: $dir"
             return 1
        fi
        log "DEBUG" "Directorio '$dir' configurado: Propietario=$owner_group, Permisos=775."
    done
    return 0
}

#--- Instalación de Sonarr (Mejorada para Idempotencia y Robustez) ---
install_sonarr() {
    local sonarr_executable="${CONFIG[INSTALL_DIR]}/${CONFIG[EXECUTABLE_NAME]}"

    # --- Verificación de Idempotencia ---
    if [[ -x "$sonarr_executable" ]]; then
        # Podrías añadir una comprobación de versión aquí si quieres implementar actualizaciones
        local current_version
        current_version=$("$sonarr_executable" --version 2>/dev/null || echo "desconocida") # Asumiendo que Sonarr tiene una opción de versión
        log "INFO" "Sonarr ya parece estar instalado en '$sonarr_executable' (Versión: $current_version). Saltando descarga y extracción."
        # Asegurar permisos correctos incluso si ya existe
        log "INFO" "Asegurando permisos correctos en ${CONFIG[INSTALL_DIR]}..."
        chown -R "${CONFIG[SERVICE_USER]}":"${CONFIG[SERVICE_GROUP]}" "${CONFIG[INSTALL_DIR]}" || log "WARN" "No se pudieron re-aplicar permisos en ${CONFIG[INSTALL_DIR]}"
        chmod -R u+rwX,g+rwX,o+rX,o-w "${CONFIG[INSTALL_DIR]}" || log "WARN" "No se pudieron re-aplicar permisos en ${CONFIG[INSTALL_DIR]}" # Equivalente a 775 para directorios, 664/775 para archivos
        return 0
    fi

    log "INFO" "Procediendo con la instalación de Sonarr..."

    # --- Detección de Arquitectura ---
    log "INFO" "Detectando arquitectura del sistema..."
    local arch dl_arch
    arch=$(dpkg --print-architecture)
    # Usar un case es más legible y seguro que tr/grep/cut
    case "$arch" in
        amd64) dl_arch="x64" ;;
        armhf) dl_arch="arm" ;;
        arm64) dl_arch="arm64" ;;
        *) log "ERROR" "Arquitectura no soportada por este script: $arch"; return 1 ;;
    esac
    log "INFO" "Arquitectura detectada: $arch (Mapeada a: $dl_arch para Sonarr)"

    # --- Descarga Segura ---
    local dl_url="${CONFIG[RELEASE_URL]}&arch=$dl_arch"
    local temp_file
    # Crear archivo temporal de forma segura
    temp_file=$(mktemp --suffix=.tar.gz) || { log "ERROR" "No se pudo crear archivo temporal."; return 1; }
    # Usar download_secure de utils.sh
    log "INFO" "Descargando Sonarr ($dl_arch) desde: $dl_url"
    if ! download_secure "$dl_url" "$temp_file"; then
        log "ERROR" "Fallo en la descarga de Sonarr."
        rm -f "$temp_file" # Limpiar archivo temporal
        return 1
    fi

    # --- Extracción Controlada ---
    log "INFO" "Extrayendo archivos a ${CONFIG[INSTALL_DIR]}..."
    # Asegurar que el directorio de instalación existe (debería haber sido creado por configure_directories)
    mkdir -p "${CONFIG[INSTALL_DIR]}" || { log "ERROR" "No se pudo asegurar la existencia del directorio de instalación: ${CONFIG[INSTALL_DIR]}"; rm -f "$temp_file"; return 1; }

    # Extraer contenido directamente en INSTALL_DIR, eliminando el directorio raíz del tarball (asume que es 'Sonarr/')
    # El --strip-components=1 elimina el primer nivel de directorio dentro del archivo tar.gz
    if ! tar -xzf "$temp_file" --strip-components=1 -C "${CONFIG[INSTALL_DIR]}"; then
        log "ERROR" "Error al extraer los archivos de Sonarr a ${CONFIG[INSTALL_DIR]}"
        rm -f "$temp_file"
        # Podríamos intentar limpiar ${CONFIG[INSTALL_DIR]} si falló la extracción
        # find "${CONFIG[INSTALL_DIR]}" -mindepth 1 -delete
        return 1
    fi

    log "INFO" "Archivos extraídos correctamente."
    rm -f "$temp_file" # Limpiar archivo temporal

    # --- Establecer Permisos Post-Extracción ---
    log "INFO" "Estableciendo propietario y permisos en ${CONFIG[INSTALL_DIR]}..."
    if ! chown -R "${CONFIG[SERVICE_USER]}":"${CONFIG[SERVICE_GROUP]}" "${CONFIG[INSTALL_DIR]}"; then
         log "ERROR" "Fallo al establecer propietario/grupo en ${CONFIG[INSTALL_DIR]}"
         return 1
    fi
    # Ajustar permisos después de la extracción (asegurar ejecución, etc.)
    # ug=rwX asegura lectura/escritura/ejecución(directorios) para user/group
    # o=rX asegura lectura/ejecución(directorios) para otros
    # o-w quita escritura para otros
    if ! chmod -R u=rwX,g=rwX,o=rX,o-w "${CONFIG[INSTALL_DIR]}"; then
         log "ERROR" "Fallo al establecer permisos en ${CONFIG[INSTALL_DIR]}"
         return 1
    fi

    log "INFO" "Instalación de Sonarr completada en ${CONFIG[INSTALL_DIR]}"
    return 0
}

#--- Configuración del Servicio Systemd (Idempotente en efecto) ---
configure_service() {
    log "INFO" "Configurando el servicio systemd para Sonarr..."

    # Usar create_backup de utils.sh antes de sobrescribir
    if ! create_backup "${CONFIG[SERVICE_FILE]}"; then
        log "WARN" "No se pudo crear un backup de ${CONFIG[SERVICE_FILE]}. Continuando..."
        # No retornar 1 aquí, ya que podría ser la primera ejecución
    fi

    # Crear/Sobrescribir el archivo de servicio
    # Asegurarse que ExecStart apunta al ejecutable correcto dentro de INSTALL_DIR
    local exec_start="${CONFIG[INSTALL_DIR]}/${CONFIG[EXECUTABLE_NAME]}"
    local data_dir_param="-data=${CONFIG[DATA_DIR]}"

    # Usar cat con EOF para crear el archivo de servicio
    cat > "${CONFIG[SERVICE_FILE]}" <<EOF
[Unit]
Description=Sonarr Daemon (Managed by Confiraspa)
After=syslog.target network-online.target
Wants=network-online.target

[Service]
User=${CONFIG[SERVICE_USER]}
Group=${CONFIG[SERVICE_GROUP]}
UMask=${CONFIG[UMASK]}          # Asegura permisos de archivos creados por Sonarr
Type=simple
# Ejecutar Sonarr sin abrir navegador y especificando el directorio de datos
ExecStart=${exec_start} -nobrowser ${data_dir_param}
TimeoutStopSec=20
KillMode=process
Restart=on-failure
# Opcional: Limitar recursos si es necesario en una RPi
# CPUWeight=100
# MemoryMax=1G # Ajustar según la RPi

[Install]
WantedBy=multi-user.target
EOF

    # Verificar si el archivo se creó/modificó
    if [[ ! -f "${CONFIG[SERVICE_FILE]}" ]]; then
        log "ERROR" "Fallo al crear el archivo de servicio: ${CONFIG[SERVICE_FILE]}"
        return 1
    fi
    # Establecer permisos recomendados para archivos de servicio
    chmod 644 "${CONFIG[SERVICE_FILE]}"

    log "INFO" "Recargando configuración de systemd (daemon-reload)..."
    if ! systemctl daemon-reload; then
        log "ERROR" "Fallo al ejecutar systemctl daemon-reload."
        return 1
    fi

    log "INFO" "Habilitando e iniciando el servicio Sonarr (enable --now)..."
    # enable --now es idempotente (habilita si no lo está, inicia si no lo está)
    if ! systemctl enable --now "${CONFIG[APP_NAME]}.service"; then
        log "ERROR" "Fallo al habilitar o iniciar el servicio ${CONFIG[APP_NAME]}."
        # Mostrar logs del servicio para diagnóstico
        log "INFO" "Mostrando últimos logs del servicio ${CONFIG[APP_NAME]}..."
        journalctl -u "${CONFIG[APP_NAME]}" -n 20 --no-pager
        return 1
    fi

    log "INFO" "Servicio ${CONFIG[APP_NAME]} configurado, habilitado e iniciado."
    return 0
}

#--- Verificación de la Instalación (Mejorada) ---
verify_installation() {
    log "INFO" "Verificando estado del servicio Sonarr..."

    # Esperar un momento para que el servicio termine de iniciar
    sleep 5

    if ! systemctl is-active --quiet "${CONFIG[APP_NAME]}.service"; then
        log "ERROR" "El servicio ${CONFIG[APP_NAME]} no está activo después del inicio."
        log "INFO" "Mostrando estado detallado del servicio..."
        systemctl status "${CONFIG[APP_NAME]}.service" --no-pager
        log "INFO" "Mostrando últimos logs del servicio ${CONFIG[APP_NAME]}..."
        journalctl -u "${CONFIG[APP_NAME]}" -n 50 --no-pager
        return 1
    fi

    log "INFO" "Servicio ${CONFIG[APP_NAME]} está activo."

    # Verificación adicional: intentar conectar al puerto localmente
    local local_url="http://127.0.0.1:${CONFIG[PORT]}"
    log "INFO" "Intentando conectar a la interfaz web localmente en ${local_url}..."
    # Usar curl con --fail para retornar error si HTTP status >= 400, --silent para no mostrar salida, --max-time corto
    if ! curl --fail --silent --max-time 10 "$local_url" > /dev/null; then
         log "WARN" "No se pudo conectar a $local_url. El servicio podría estar tardando en responder o haber un problema de configuración interno de Sonarr."
         log "WARN" "A pesar de esto, el servicio systemd está reportado como activo."
         # No retornamos error aquí, ya que el servicio *está* activo según systemd.
    else
         log "INFO" "Conexión local a $local_url exitosa."
    fi

    # Obtener IP para mensaje final usando la función de utils.sh
    local ip_address
    ip_address=$(get_ip_address) || ip_address="<IP no detectada>"

    log "SUCCESS" "Instalación y configuración de Sonarr completadas."
    log "INFO" "Puedes acceder a la interfaz web en: http://${ip_address}:${CONFIG[PORT]}"
    log "INFO" "Usuario/Grupo de ejecución: ${CONFIG[SERVICE_USER]}/${CONFIG[SERVICE_GROUP]}"
    log "INFO" "Directorio de instalación: ${CONFIG[INSTALL_DIR]}"
    log "INFO" "Directorio de datos: ${CONFIG[DATA_DIR]}"
    return 0
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Flujo Principal del Script (main)
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
main() {
    # --- Configuración Inicial Esencial ---
    # setup_error_handling y setup_paths son llamados por utils.sh al ser sourced si está bien diseñado,
    # o necesitan ser llamados explícitamente si no. Asumiendo que setup_paths es llamado por utils.sh
    # y setup_error_handling también (o se llama aquí).
    setup_error_handling # Asegurar que se llama

    log "INFO" "== Iniciando script de instalación/configuración de Sonarr =="

    # Verificar si se ejecuta como root
    check_root || exit 1 # Usar exit 1 si las funciones de utils retornan > 0 en fallo

    # Verificar conectividad básica (opcional, pero bueno antes de instalar deps)
    check_network_connectivity # No salir si falla, sólo advertir

    # --- Carga de Configuración Específica ---
    load_user_config || exit 1

    # --- Preparación del Sistema ---
    setup_system_user || exit 1
    configure_directories || exit 1

    # --- Instalación de Dependencias ---
    # install_dependencies de utils.sh maneja la idempotencia
    log "INFO" "Instalando dependencias necesarias..."
    install_dependencies curl sqlite3 wget jq || exit 1
    # Considerar añadir .NET SDK/Runtime aquí si es necesario para Sonarr v4+

    # --- Instalación de la Aplicación ---
    install_sonarr || exit 1

    # --- Configuración del Servicio ---
    configure_service || exit 1

    # --- Verificación Final ---
    verify_installation || exit 1 # Salir si la verificación crucial falla

    log "INFO" "== Script de Sonarr finalizado con éxito =="
    exit 0
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Ejecución del Script
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Pasar todos los argumentos recibidos por el script a la función main
main "$@"