#!/bin/bash
# Biblioteca de utilidades comunes para scripts de Confiraspa
# Proporciona funciones estándar para logging, manejo de errores, dependencias, etc.
# Version: utils-1.2.0 (Añadido backup/restore, mejoras menores)

# --- Configuración Global: Variables Esenciales ---
export INSTALL_DIR
INSTALL_DIR="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
export CONFIG_DIR="${INSTALL_DIR}/configs" # Directorio con las configuraciones
export LOG_DIR="${INSTALL_DIR}/logs"       # Directorio de logs
LOG_FILE="" # Definido por setup_paths()

# --- Función: Logging Estandarizado ---
log() {
    mkdir -p "$LOG_DIR" 2>/dev/null # Intentar asegurar, ignorar error si falla aquí

    local level="${1:-INFO}"
    local message="$2"
    local timestamp
    timestamp=$(date --iso-8601=seconds)
    local script_caller_name
    # Intenta obtener el nombre del script que llama (índice 1 de BASH_SOURCE)
    # Fallback a $0 si no está disponible (ej. llamado desde prompt)
    script_caller_name=$(basename "${BASH_SOURCE[1]:-$0}")

    local log_entry="[${timestamp}] [${level}] [${script_caller_name}] ${message}"

    # Imprime en stderr para no interferir con la salida estándar del script
    # y añade al log general.
    echo "${log_entry}" | tee -a "${LOG_DIR}/confiraspa.log" >&2

    # Escribir también al log específico del script si LOG_FILE está definido y es escribible
    if [[ -n "$LOG_FILE" && -w "$LOG_FILE" ]]; then
        echo "${log_entry}" >> "$LOG_FILE"
    fi
}

# --- Funciones: Configuración Inicial y Manejo de Errores ---
setup_error_handling() {
    set -eo pipefail
    # Añadido código de salida $? al trap
    trap 'log "ERROR" "Error crítico en línea $LINENO (código $?). Último comando ejecutado: $BASH_COMMAND"' ERR
}

setup_paths() {
    # Usar echo directo a stderr para errores tempranos antes de que log() esté garantizado
    [[ -z "$INSTALL_DIR" || -z "$CONFIG_DIR" || -z "$LOG_DIR" ]] && {
        echo "[$(date --iso-8601=seconds)] [ERROR] [setup_paths] Variables de directorio base no definidas correctamente." >&2
        return 1
    }

    local dirs=("$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR")
    local failed=0
    local dir
    local script_name

    # Usar echo directo aquí, ya que log() aún no está completamente listo
    echo "[$(date --iso-8601=seconds)] [INFO] [setup_paths] Asegurando existencia y permisos de directorios base: ${dirs[*]}" >&2

    for dir in "${dirs[@]}"; do
        if ! mkdir -p "$dir"; then
            echo "[$(date --iso-8601=seconds)] [ERROR] [setup_paths] No se pudo crear o acceder al directorio: $dir (Verifica permisos padres)" >&2
            failed=1
            continue
        fi
        # 755 es razonable para directorios base compartidos
        if ! chmod 755 "$dir"; then
             echo "[$(date --iso-8601=seconds)] [ERROR] [setup_paths] No se pudieron establecer permisos 755 en: $dir" >&2
            failed=1
        fi
    done

    script_name=$(basename "$0")
    script_name="${script_name%.sh}" # Nombre sin extensión .sh
    # Definir la variable global LOG_FILE
    LOG_FILE="${LOG_DIR}/${script_name}.log"

    # Crear archivo de log específico y establecer permisos (640: rw- r-- ---)
    # Asegurarse de que el usuario/grupo propietario sea correcto (normalmente root si se ejecuta con sudo)
    if ! touch "$LOG_FILE"; then
        echo "[$(date --iso-8601=seconds)] [ERROR] [setup_paths] No se pudo crear o acceder al archivo de log específico: $LOG_FILE" >&2
        # No marcamos como fallo fatal aquí, el log general aún podría funcionar
    else
        if ! chmod 640 "$LOG_FILE"; then
            echo "[$(date --iso-8601=seconds)] [ERROR] [setup_paths] No se pudieron establecer permisos 640 en: $LOG_FILE" >&2
        fi
        # Asegurar propiedad correcta (asumiendo ejecución con sudo)
        # chown root:adm "$LOG_FILE" # O root:root según necesidad
    fi

    # Ahora log() debería funcionar correctamente
    if [ $failed -eq 0 ]; then
        log "INFO" "Directorios base y archivo de log específico ($LOG_FILE) configurados."
    else
        log "WARN" "Hubo errores al configurar directorios o archivo de log. Revisa los mensajes anteriores."
    fi

    return $failed
}

# --- Funciones: Verificaciones y Validaciones ---
check_root() {
    [[ $EUID -eq 0 ]] || {
        log "ERROR" "Este script requiere privilegios de superusuario (root). Ejecute con: sudo $0 $*"
        exit 1
    }
}

check_network_connectivity() {
    local target_host="${1:-8.8.8.8}" # DNS Google por defecto
    local ping_count="${2:-1}"       # 1 ping es suficiente
    log "DEBUG" "Verificando conectividad a Internet (ping -c $ping_count $target_host)..."
    # Añadido timeout (-W 2) para no esperar indefinidamente si no hay ruta
    if ! ping -c "$ping_count" -W 2 "$target_host" &>/dev/null; then
        log "WARN" "No se detectó conexión a Internet hacia $target_host. Algunas operaciones (como instalar dependencias) podrían fallar."
        return 1 # Devuelve fallo, pero no sale
    fi
    log "INFO" "Conectividad a Internet verificada ($target_host)."
    return 0
}

is_package_installed() {
    local package="$1"
    dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"
}

# --- Funciones: Gestión de Paquetes ---
get_installed_version() {
    local package="$1"
    dpkg-query -W -f='${Version}' "$package" 2>/dev/null || echo "" # Devuelve vacío si no encontrado
}

install_dependencies() {
    local deps=("$@")
    local dep
    local missing_deps=()

    log "INFO" "Verificando dependencias requeridas: ${deps[*]}"
    for dep in "${deps[@]}"; do
        if ! is_package_installed "$dep"; then
            missing_deps+=("$dep")
        else
             local version
             version=$(get_installed_version "$dep")
             log "DEBUG" "Dependencia ya instalada: $dep (Versión: ${version:-n/a})"
        fi
    done

    if [ ${#missing_deps[@]} -eq 0 ]; then
        log "INFO" "Todas las dependencias requeridas ya están instaladas."
        return 0
    fi

    log "INFO" "Se instalarán las siguientes dependencias faltantes: ${missing_deps[*]}"

    # Verificar conectividad antes de intentar apt-get update/install
    if ! check_network_connectivity; then
         log "ERROR" "No hay conexión a Internet. No se pueden instalar dependencias."
         return 1
    fi

    log "INFO" "Actualizando lista de paquetes (apt-get update)..."
    if ! apt-get update -qq; then
        log "ERROR" "Fallo al ejecutar 'apt-get update'. Verifica tu conexión y configuración de repositorios."
        return 1
    fi

    log "INFO" "Instalando paquetes: ${missing_deps[*]}"
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing_deps[@]}"; then
         log "ERROR" "Fallo al instalar uno o más paquetes: ${missing_deps[*]}"
         return 1
    fi

    log "SUCCESS" "Dependencias instaladas correctamente: ${missing_deps[*]}"
    return 0
}

# --- Funciones: Operaciones de Red y Sistema ---
get_ip_address() {
    hostname -I | awk '{print $1}' || echo "127.0.0.1"
}

# --- Funciones: Gestión de Archivos y Backups ---

# Crea un backup timestamped de un archivo en el mismo directorio
# Uso: create_backup "/ruta/al/archivo"
# Retorna: 0 en éxito, 1 en fallo.
create_backup() {
    local filepath="$1"
    local backup_dir
    local filename
    local timestamp
    local backup_file

    [[ -z "$filepath" ]] && { log "ERROR" "(create_backup) No se proporcionó ruta de archivo."; return 1; }
    # Es normal que el archivo no exista la primera vez
    [[ ! -f "$filepath" ]] && { log "DEBUG" "(create_backup) El archivo a respaldar no existe aún: $filepath"; return 0; }

    backup_dir=$(dirname "$filepath")
    filename=$(basename "$filepath")
    timestamp=$(date +%Y%m%d_%H%M%S)
    # Asegurar que el nombre del backup sea válido (evitar dobles puntos si filename tiene puntos)
    backup_file="${backup_dir}/${filename}.${timestamp}.bak"

    log "INFO" "Creando backup de '$filename' en '$backup_file'"
    # -a preserva permisos, propietario, timestamp
    if ! cp -a "$filepath" "$backup_file"; then
        log "ERROR" "No se pudo crear el backup: $backup_file"
        return 1
    fi
    log "DEBUG" "Backup creado con éxito: $backup_file"
    return 0
}

# Restaura el backup más reciente de un archivo (con extensión .bak)
# Uso: restore_backup "/ruta/al/archivo"
# Retorna: 0 en éxito, 1 si no hay backups o falla la restauración.
restore_backup() {
    local filepath="$1"
    local backup_dir
    local filename
    local latest_backup

    [[ -z "$filepath" ]] && { log "ERROR" "(restore_backup) No se proporcionó ruta de archivo."; return 1; }

    backup_dir=$(dirname "$filepath")
    filename=$(basename "$filepath")

    # Encontrar el backup más reciente basado en el timestamp del nombre
    # Usar find + sort es más robusto con nombres raros que ls -t
    # Buscar archivos que empiecen con el nombre, seguido de punto, 8 dígitos, _, 6 dígitos, punto, bak
    # y luego ordenarlos y tomar el último (más reciente)
    latest_backup=$(find "$backup_dir" -maxdepth 1 -name "${filename}.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9].bak" -print0 | sort -zV | tail -zn 1 | tr '\0' '\n')

    if [[ -z "$latest_backup" || ! -f "$latest_backup" ]]; then
        log "WARN" "(restore_backup) No se encontraron backups (.YYYYMMDD_HHMMSS.bak) válidos para: $filepath"
        return 1
    fi

    log "INFO" "Restaurando el backup más reciente: $latest_backup -> $filepath"
    # Usar mv es atómico si está en el mismo filesystem, preferible a cp+rm
    if ! mv -f "$latest_backup" "$filepath"; then
        log "ERROR" "Fallo al restaurar (mv) el backup $latest_backup a $filepath"
        # Intentar con cp como fallback si mv falla por alguna razón (ej. cross-device)
        if ! cp -a "$latest_backup" "$filepath"; then
             log "ERROR" "Fallo también al restaurar con cp el backup $latest_backup a $filepath"
             return 1
        else
             log "INFO" "Backup restaurado con cp (mv falló). El archivo .bak original ($latest_backup) aún existe."
        fi
    fi

    log "SUCCESS" "Backup restaurado con éxito a $filepath."
    # Opcional: Eliminar otros backups antiguos si se desea
    # find "$backup_dir" -maxdepth 1 -name "${filename}.*.bak" -type f ! -name "$(basename "$latest_backup")" -delete

    return 0
}


# --- Funciones: Acciones (Descarga, etc.) ---
# (La función download_secure ya estaba completa y correcta)
download_secure() {
    local url="$1"
    local output="$2"
    local expected_sha256="$3"

    log "INFO" "Descargando archivo desde: $url"
    log "DEBUG" "Guardando en: $output"

    # Añadido --connect-timeout 10 y --max-time 300 (5 min)
    if ! curl --connect-timeout 10 --max-time 300 -fsSL -o "$output" "$url"; then
        log "ERROR" "Falló la descarga desde $url (Error HTTP, de red o timeout)"
        rm -f "$output" # Limpiar archivo parcial
        return 1
    fi

    if [[ -n "$expected_sha256" ]]; then
        log "INFO" "Verificando integridad del archivo (SHA256)..."
        local actual_sha256
        # Usar BASH_CMDSUBST_IGNORE_EOLNS=1 para manejar nombres de archivo con espacios/saltos de línea correctamente
        # O simplemente asegurar que no haya saltos de línea en la salida
        actual_sha256=$(sha256sum "$output" | awk '{print $1}')

        if [[ "$actual_sha256" != "$expected_sha256" ]]; then
            log "ERROR" "¡Verificación SHA256 fallida para $output!"
            log "ERROR" "  Esperado: $expected_sha256"
            log "ERROR" "  Obtenido: $actual_sha256"
            rm -f "$output" # Eliminar archivo corrupto/incorrecto
            return 1
        else
            log "INFO" "Verificación SHA256 exitosa para $output."
        fi
    else
        log "WARN" "No se proporcionó hash SHA256 esperado para $url. No se verificó la integridad."
    fi

    log "INFO" "Archivo descargado correctamente: $output"
    return 0
}


# --- Fin de la Biblioteca de Utilidades ---