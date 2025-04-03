#!/bin/bash

# Script: setup_logrotate_from_json.sh
# Descripción: Configura logrotate para rotar logs según especificaciones en JSON
# Autor: Tu Nombre (Modificado por Asistente AI)
# Versión: 2.1.0 (Integración con utils-1.2.0, backup/restore, mejoras)
# Uso: sudo ./setup_logrotate_from_json.sh [archivo_json_opcional]

# --- Cargar Funciones Comunes ---
# Asume que utils.sh está en ../lib relativo a este script o en la ruta absoluta
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
UTILS_LIB="/opt/confiraspa/lib/utils.sh" # Ruta absoluta preferida

if [[ ! -f "$UTILS_LIB" ]]; then
    echo "ERROR: Biblioteca de utilidades no encontrada en $UTILS_LIB" >&2
    exit 1
fi
# shellcheck source=/opt/confiraspa/lib/utils.sh
source "$UTILS_LIB"

# --- Configuración Inicial ---
setup_error_handling # Configura set -eo pipefail y trap ERR
check_root           # Asegura ejecución como root
# setup_paths se llama DESPUÉS de definir variables como json_file
# check_network_connectivity se llama ANTES de install_dependencies

# --- Variables y Configuración ---
declare -a REQUIRED_PACKAGES=("jq" "logrotate")
# Permite pasar un archivo JSON como argumento, si no, usa el default
json_file_arg="$1"
json_file="${json_file_arg:-${CONFIG_DIR}/logrotate_jobs_config.json}" # Usa default si no hay argumento

# --- Funciones Específicas ---

# Valida la estructura básica del JSON y la existencia de campos clave
validate_json_config() {
    local json_path="$1"
    log "DEBUG" "Validando estructura básica del archivo JSON: $json_path"
    # Comprueba si es un JSON válido y si el array 'jobs' existe y no está vacío
    if ! jq -e '. | has("jobs") and (.jobs | length > 0)' "$json_path" >/dev/null; then
        log "ERROR" "Archivo JSON inválido o el array 'jobs' no existe o está vacío en '$json_path'"
        return 1
    fi
    # Comprueba si todos los trabajos tienen los campos mínimos requeridos
    if ! jq -e '.jobs[] | select(has("name") and has("path") and has("rotate"))' "$json_path" >/dev/null; then
         log "ERROR" "Al menos un trabajo en '$json_path' carece de los campos obligatorios 'name', 'path' o 'rotate'."
         return 1
    fi
    log "DEBUG" "Validación básica de estructura JSON completada para '$json_path'."
    return 0
}

# Genera el contenido de un archivo de configuración de logrotate
# Uso: config_content=$(generate_logrotate_config_content "$job_json")
generate_logrotate_config_content() {
    local job_data="$1" # Pasar el JSON del trabajo como string
    local path rotate frequency compress missingok notifempty create postrotate owner group mode

    # Extraer valores usando jq, proporcionando defaults o manejando nulls
    path=$(jq -r '.path' <<< "$job_data")
    rotate=$(jq -r '.rotate' <<< "$job_data")
    frequency=$(jq -r '.frequency // empty' <<< "$job_data") # // empty devuelve vacío si es null o no existe
    compress=$(jq -r '.compress // "true"' <<< "$job_data") # Default a true si no se especifica
    missingok=$(jq -r '.missingok // "true"' <<< "$job_data") # Default a true
    notifempty=$(jq -r '.notifempty // "true"' <<< "$job_data") # Default a true
    create=$(jq -r '.create // empty' <<< "$job_data")
    postrotate=$(jq -r '.postrotate // empty' <<< "$job_data")
    # Opcional: Añadir soporte para owner, group, mode en 'create'
    # owner=$(jq -r '.owner // empty' <<< "$job_data")
    # group=$(jq -r '.group // empty' <<< "$job_data")
    # mode=$(jq -r '.mode // empty' <<< "$job_data")

    # Construir el contenido
    {
        echo "$path {"
        echo "    rotate $rotate"
        [[ -n "$frequency" ]] && echo "    $frequency"
        [[ "$compress" == "true" ]] && echo "    compress" || echo "    nocompress" # Más explícito
        [[ "$missingok" == "true" ]] && echo "    missingok"
        [[ "$notifempty" == "true" ]] && echo "    notifempty"
        # Construir la línea 'create' si se especifica
        if [[ -n "$create" ]]; then
            # Podría expandirse para incluir owner/group si se añaden arriba
            echo "    create $create"
        fi
        if [[ -n "$postrotate" ]]; then
            # Usar printf para manejar correctamente los saltos de línea en postrotate
            printf "    postrotate\n%s\n    endscript\n" "$postrotate"
        fi
        echo "}"
    }
}

# --- Ejecución Principal ---
main() {
    # Configurar rutas ahora que las variables base están definidas
    # El log específico se creará/configurará aquí
    if ! setup_paths; then
        # setup_paths ya loguea el error, simplemente salimos si falla
        exit 1
    fi

    log "INFO" "-----------------------------------------------------"
    log "INFO" "Iniciando script de configuración de Logrotate"
    log "INFO" "Usando archivo de configuración: $json_file"
    log "INFO" "-----------------------------------------------------"

    # 1. Verificar conectividad (necesaria para dependencias)
    check_network_connectivity # Ahora solo advierte si falla

    # 2. Instalar dependencias (jq, logrotate)
    if ! install_dependencies "${REQUIRED_PACKAGES[@]}"; then
        log "ERROR" "No se pudieron instalar las dependencias requeridas. Abortando."
        exit 1
    fi

    # 3. Validar archivo de configuración JSON
    if [[ ! -f "$json_file" ]]; then
        log "ERROR" "Archivo de configuración no encontrado: $json_file"
        exit 1
    fi
    if ! validate_json_config "$json_file"; then
        # La validación ya logueó el error específico
        exit 1
    fi

    log "INFO" "Procesando trabajos de logrotate desde: $json_file"
    local errors_found=0 # Contador para errores no fatales

    # 4. Procesar cada trabajo definido en el JSON
    # Usar mapfile/readarray para leer en array si se prefiere evitar el 'while read' pipe
    # Pero 'while read' es más eficiente en memoria para archivos grandes
    jq -c '.jobs[]' "$json_file" | while IFS= read -r job_json; do
        local job_name config_file desired_config_content current_config_content config_changed=false
        local temp_config_file

        job_name=$(jq -r '.name' <<< "$job_json")

        # Validación mínima del nombre (no vacío, sin barras)
        if [[ -z "$job_name" || "$job_name" == *"/"* ]]; then
            log "ERROR" "Nombre de trabajo inválido ('$job_name') en JSON. Saltando este trabajo."
            errors_found=$((errors_found + 1))
            continue
        fi

        log "INFO" "Procesando trabajo: '$job_name'"
        config_file="/etc/logrotate.d/${job_name}"

        # 5. Generar el contenido de configuración deseado
        desired_config_content=$(generate_logrotate_config_content "$job_json")
        if [[ -z "$desired_config_content" ]]; then
            log "ERROR" "No se pudo generar el contenido de configuración para '$job_name'. Saltando."
            errors_found=$((errors_found + 1))
            continue
        fi

        # 6. Comprobar si el archivo existente necesita cambios
        if [[ -f "$config_file" ]]; then
            current_config_content=$(cat "$config_file")
            # Comparar contenido directamente
            if [[ "$desired_config_content" == "$current_config_content" ]]; then
                log "INFO" "Configuración para '$job_name' ya está actualizada. No se requieren cambios."
                continue # Pasar al siguiente trabajo
            else
                log "INFO" "Configuración existente para '$job_name' difiere. Se actualizará."
                config_changed=true
                # Crear backup ANTES de sobreescribir
                if ! create_backup "$config_file"; then
                    log "WARN" "No se pudo crear backup para '$config_file'. Continuando con precaución."
                    # Podrías decidir abortar aquí si el backup es crítico:
                    # errors_found=$((errors_found + 1)); continue
                fi
            fi
        else
            log "INFO" "Creando nuevo archivo de configuración para '$job_name'."
            config_changed=true
        fi

        # 7. Escribir configuración a archivo temporal y validar sintaxis
        temp_config_file=$(mktemp)
        echo "$desired_config_content" > "$temp_config_file"

        log "DEBUG" "Validando sintaxis de la nueva configuración para '$job_name'..."
        # logrotate -d escribe mucho a stderr, redirigir a /dev/null si la validación es exitosa
        if ! logrotate -d "$temp_config_file" >/dev/null 2>&1; then
            log "ERROR" "¡Configuración generada para '$job_name' es inválida según 'logrotate -d'!"
            # Mostrar el error de logrotate -d para depuración
            log "ERROR" "Salida de 'logrotate -d $temp_config_file':"
            logrotate -d "$temp_config_file" # Sin redirigir stderr esta vez
            rm "$temp_config_file"
            errors_found=$((errors_found + 1))

            # Intentar restaurar backup si existía un archivo previo
            if [[ -f "$config_file" ]]; then
                log "INFO" "Intentando restaurar backup para '$config_file'..."
                if ! restore_backup "$config_file"; then
                    log "ERROR" "¡No se pudo restaurar el backup! El archivo '$config_file' puede estar ausente o incorrecto."
                fi
            fi
            continue # Pasar al siguiente trabajo
        fi

        log "DEBUG" "Sintaxis validada correctamente para '$job_name'."

        # 8. Aplicar la nueva configuración (mover desde temporal)
        log "INFO" "Aplicando nueva configuración para '$job_name'..."
        if ! mv "$temp_config_file" "$config_file"; then
             log "ERROR" "No se pudo mover '$temp_config_file' a '$config_file'. Verifica permisos."
             rm "$temp_config_file" # Limpiar temporal
             errors_found=$((errors_found + 1))
             # Intentar restaurar backup si habíamos hecho uno
             if [[ "$config_changed" == true && -f "$config_file.bak"* ]]; then # Aproximación simple
                 restore_backup "$config_file" || log "ERROR" "Fallo al restaurar backup tras error de mv."
             fi
             continue
        fi
        # Asegurar permisos correctos (logrotate suele requerir 644 o más restrictivo)
        chmod 644 "$config_file"
        # Opcional: chown root:root "$config_file"

        log "INFO" "Configuración para '$job_name' aplicada exitosamente."

    done # Fin del bucle while read

    log "INFO" "-----------------------------------------------------"
    if [ $errors_found -eq 0 ]; then
        log "SUCCESS" "Proceso de configuración de Logrotate completado sin errores."
    else
        log "WARN" "Proceso de configuración de Logrotate completado con $errors_found error(es)."
        log "INFO" "-----------------------------------------------------"
        return 1 # Indicar fallo parcial
    fi
    log "INFO" "-----------------------------------------------------"
    return 0
}

# --- Ejecutar Script ---
# Pasa los argumentos del script a main() si es necesario (aunque aquí no se usan directamente en main)
main "$@"

# Fin del script