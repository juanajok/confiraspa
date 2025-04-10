#!/bin/bash
### Descripción: Configura tareas programadas (cron jobs) para root de forma segura e idempotente
###              basándose en un archivo JSON, con soporte para intérpretes específicos.
### Versión: 2.1.0 (Añadido soporte para campo 'interpreter' en JSON)

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Carga de biblioteca de utilidades y configuración inicial
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
source "/opt/confiraspa/lib/utils.sh" || {
    echo "[ERROR] [$(basename "$0")] Error crítico: No se puede cargar la biblioteca /opt/confiraspa/lib/utils.sh" >&2
    exit 1
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Configuración Global
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Archivo JSON con la lista de tareas cron.
# Formato: [{"script": "script.sh", "schedule": "0 * * * *", "interpreter": null, "description": "Tarea diaria"}, ...]
declare -r CONFIG_FILE="${CONFIG_DIR}/scripts_and_crontab.json"
declare -r SCRIPTS_BASE_DIR="${INSTALL_DIR}/scripts"
declare -r CRON_JOB_TAG="# Confiraspa Job"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Funciones Auxiliares (validate_cron_schedule, check_exact_cron_entry - sin cambios)
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
validate_cron_schedule() {
    local schedule="$1"
    local cron_regex='^(@(annually|yearly|monthly|weekly|daily|hourly|reboot))|(([-*,0-9/L#? ]{1,100})|([ \t]+)){5,6}$'
    if [[ ! "$schedule" =~ $cron_regex ]]; then log "ERROR" "Formato schedule inválido: '$schedule'"; return 1; fi
    if [[ -z "$schedule" ]]; then log "ERROR" "Schedule no puede estar vacío."; return 1; fi
    return 0
}
check_exact_cron_entry() {
    local full_cron_line="$1"
    if (crontab -l 2>/dev/null || true) | grep -Fxq -- "$full_cron_line"; then return 0; else return 1; fi
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Proceso Principal
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
main() {
    # --- Inicialización y Verificaciones ---
    setup_error_handling
    check_root
    install_dependencies "jq" || exit 1
    # setup_paths || exit 1 # Descomentar si no se llama desde utils.sh

    log "INFO" "== Iniciando configuración de Crontab v2.1.0 para root desde ${CONFIG_FILE} =="

    if [[ ! -f "$CONFIG_FILE" ]]; then log "ERROR" "Archivo config no encontrado: ${CONFIG_FILE}"; exit 1; fi

    # --- Backup ---
    local timestamp backup_file
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_file="${LOG_DIR}/crontab_root_backup_${timestamp}.bak"
    log "INFO" "Creando backup crontab root actual en ${backup_file}"
    if ! crontab -l > "$backup_file" 2>/dev/null; then
        if [[ $? -eq 1 ]]; then
            log "INFO" "No se encontró crontab existente para root."
            touch "$backup_file" || log "WARN" "No se pudo crear archivo backup vacío."
        else
            log "ERROR" "Error leyendo crontab root para backup."; exit 1
        fi
    fi

    # --- Procesar JSON ---
    local jobs_json added_jobs skipped_jobs failed_jobs total_jobs
    added_jobs=0; skipped_jobs=0; failed_jobs=0; total_jobs=0

    # Validar que el archivo contiene un array JSON antes de procesar
    log "DEBUG" "Validando si ${CONFIG_FILE} contiene un array JSON..."
    if ! jq -e '. | type == "array"' "$CONFIG_FILE" > /dev/null 2>&1; then
        log "ERROR" "El archivo JSON '${CONFIG_FILE}' no es válido o no contiene un array JSON en el nivel superior."
        log "ERROR" "Contenido actual:"
        cat "$CONFIG_FILE" # Mostrar contenido para depuración
        exit 1
    fi

    jobs_json=$(jq -c '.[]' "$CONFIG_FILE")
    if [[ -z "$jobs_json" ]]; then log "INFO" "Archivo JSON vacío. No hay jobs que procesar."; exit 0; fi

    local current_crontab_content new_crontab_content modified=0
    current_crontab_content=$(crontab -l 2>/dev/null || true)
    new_crontab_content="${current_crontab_content}"


    log "INFO" "Procesando definiciones de jobs desde JSON..."
    while IFS= read -r job; do # Usar IFS= read -r para manejar mejor espacios/caracteres
        ((++total_jobs))

        # Extraer datos, incluyendo el nuevo campo 'interpreter'
        # Usar 'empty' como default si falta el campo en jq, y luego verificar si está vacío en bash
        script_name=$(jq -re '.script // empty' <<< "$job") || { log "WARN" "Job ${total_jobs}: Error parseando 'script'. Skipping."; ((skipped_jobs++)); continue; }
        schedule=$(jq -re '.schedule // empty' <<< "$job") || { log "WARN" "Job ${total_jobs} ('${script_name}'): Error parseando 'schedule'. Skipping."; ((skipped_jobs++)); continue; }
        interpreter=$(jq -re '.interpreter // empty' <<< "$job") || { log "WARN" "Job ${total_jobs} ('${script_name}'): Error parseando 'interpreter'. Asumiendo null/directo."; interpreter=""; } # Default a vacío si falla parseo

        if [[ -z "$script_name" || -z "$schedule" ]]; then
            log "WARN" "Job ${total_jobs}: 'script' o 'schedule' vacíos en JSON. Skipping."
            ((skipped_jobs++)); continue
        fi

        script_path="${SCRIPTS_BASE_DIR}/${script_name}"
        log "DEBUG" "Procesando Job ${total_jobs}: Script='${script_name}', Schedule='${schedule}', Interpreter='${interpreter:-[Directo]}'"

        # --- Validaciones ---
        if [[ ! -f "$script_path" ]]; then
            log "WARN" "Job '${script_name}': Script no encontrado en '${script_path}'. Skipping."
            ((skipped_jobs++)); continue
        fi

        # Determinar el comando a ejecutar basado en si hay intérprete
        if [[ -n "$interpreter" && "$interpreter" != "null" ]]; then
            # Intérprete especificado
            command_to_run="${interpreter} ${script_path}"
            # Validar que el intérprete existe y es ejecutable
            if [[ ! -x "$interpreter" ]]; then
                log "WARN" "Job '${script_name}': Intérprete '${interpreter}' no encontrado o no ejecutable. Skipping."
                ((skipped_jobs++)); continue
            fi
            # Validar que el script es legible (no necesariamente ejecutable)
            if [[ ! -r "$script_path" ]]; then
                 log "WARN" "Job '${script_name}': Script '${script_path}' no es legible. Skipping."
                 ((skipped_jobs++)); continue
            fi
        else
            # Ejecución directa (script .sh o .py con shebang)
            command_to_run="${script_path}"
            # Validar que el script es ejecutable
            if [[ ! -x "$script_path" ]]; then
                log "WARN" "Job '${script_name}': Script no ejecutable (ejec. directa): '${script_path}'. Intentando 'chmod +x'..."
                if ! chmod +x "$script_path"; then
                    log "ERROR" "Job '${script_name}': No se pudo hacer ejecutable '${script_path}'. Skipping."
                    ((skipped_jobs++)); continue
                fi
            fi
        fi

        # Validar el schedule
        if ! validate_cron_schedule "$schedule"; then
            log "WARN" "Job '${script_name}': Schedule inválido. Skipping."
            ((skipped_jobs++)); continue
        fi

        # Construir la línea completa de crontab
        cron_comment="${CRON_JOB_TAG} (${script_name})" # Añadir guión solo si hay descripción
        cron_entry_line="${schedule} ${command_to_run} ${cron_comment}"

        # --- Comprobación de Idempotencia ---
        if grep -Fxq -- "$cron_entry_line" <<< "$current_crontab_content"; then
            log "INFO" "Job '${script_name}': Entrada exacta ya existe. Skipping."
            ((skipped_jobs++)); continue
        fi

        # --- Preparar para Añadir ---
        log "INFO" "Job '${script_name}': Preparando para añadir entrada: ${schedule} $(basename "${command_to_run}")"
        if [[ -n "$new_crontab_content" && "${new_crontab_content: -1}" != $'\n' ]]; then new_crontab_content+=$'\n'; fi
        new_crontab_content+="${cron_entry_line}"$'\n'
        modified=1
        ((++added_jobs))

    done <<< "$jobs_json"

    # --- Cargar Nuevo Crontab ---
    if [[ "$modified" -eq 1 ]]; then
        log "INFO" "Se detectaron cambios. Cargando nuevo crontab..."
        if printf '%s' "$new_crontab_content" | crontab -; then
            log "SUCCESS" "Nuevo crontab cargado correctamente."
        else
            log "ERROR" "¡¡¡FALLO CRÍTICO al cargar nuevo crontab!!!"
            log "ERROR" "Revisar con 'sudo crontab -l'. Backup PREVIO en: ${backup_file}"
            failed_jobs=$added_jobs; added_jobs=0; exit 1
        fi
    else
        log "INFO" "No se realizaron modificaciones en el crontab."
    fi

    # --- Resumen Final ---
    log "INFO" "================ Resumen ================"
    log "INFO" "Total Jobs Definidos JSON : ${total_jobs}"
    log "INFO" "Jobs Añadidos Nuevos    : ${added_jobs}"
    log "INFO" "Jobs Skipped/Existentes : ${skipped_jobs}"
    [[ "$failed_jobs" -gt 0 ]] && log "ERROR" "Jobs Fallidos (Error Crítico): ${failed_jobs}"
    log "INFO" "========================================="
    log "INFO" "Verificar crontab: sudo crontab -l"
    log "INFO" "Backup previo: ${backup_file}"

    if [[ "$failed_jobs" -gt 0 ]]; then return 1; else return 0; fi
}

# --- Ejecución ---
main "$@"