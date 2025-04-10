#!/bin/bash
################################################################################
# Script Name: configure_automatic_updates.sh
# Description: Configura actualizaciones automáticas (unattended-upgrades)
#              en Raspberry Pi OS de forma segura e idempotente.
# Autor: Juan José Hipólito (Revisado por AI)
# Versión: 3.1.1 (Ajustes menores, añade get_distro_codename)
# Fecha: 2024-04-05
# Licencia: GNU GPL v3
# Uso: sudo bash configure_automatic_updates.sh
# Dependencias: unattended-upgrades, apt, lsb-release
################################################################################

# --- Configuración Inicial ---
# Asumiendo que utils.sh exporta/define INSTALL_DIR, CONFIG_DIR, LOG_DIR
source "/opt/confiraspa/lib/utils.sh" || {
    # Usar echo directo si log() puede no estar disponible
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CRITICAL] [$(basename "$0")] Fallo al cargar /opt/confiraspa/lib/utils.sh" >&2
    exit 1
}

# --- Variables Globales ---
declare -r AUTO_UPGRADES_CONFIG="/etc/apt/apt.conf.d/20auto-upgrades"
# declare -r UNATTENDED_UPGRADES_CONFIG="/etc/apt/apt.conf.d/50unattended-upgrades" # No se usa directamente si usamos overrides
declare -r LOCAL_OVERRIDES_CONFIG="/etc/apt/apt.conf.d/99confiraspa-overrides"
declare -r LOCK_FILE="/var/lock/confiraspa_updates.lock" # Usar /var/run o /run si es posible y volátil

# --- Funciones Auxiliares ---

# Obtiene el codename de la distribución (ej. bookworm, bullseye)
# Necesaria aquí si no está en utils.sh
get_distro_codename() {
    lsb_release -sc 2>/dev/null || \
    grep '^VERSION_CODENAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"' || \
    { log "ERROR" "No se pudo determinar el codename de la distribución."; return 1; }
}

# Configura una opción en un archivo estilo apt.conf de forma idempotente
# Configura una opción en un archivo estilo apt.conf de forma idempotente y segura
# Uso: configure_apt_option <file> <key> <value>
configure_apt_option() {
    local config_file="$1"
    local key="$2"
    local value="$3"
    local tmp_sed_script grep_ec=0 # Inicializar código de salida de grep a 0 (éxito)

    # Validación robusta de parámetros
    if [[ $# -ne 3 ]]; then
        log "ERROR" "[configure_apt_option] Uso incorrecto: Se requieren 3 argumentos (archivo, clave, valor)."
        return 1
    fi
    if [[ -z "$key" ]]; then
        log "ERROR" "[configure_apt_option] La clave APT proporcionada está vacía."
        return 1
    fi
    # Permitimos valor vacío, aunque en este script no se usa. Si se necesitara
    # asegurar que el valor no esté vacío, añadir: [[ -z "$value" ]] && ...

    # Asegurar directorio y archivo de configuración
    local config_dir
    config_dir=$(dirname "$config_file")
    if [[ ! -d "$config_dir" ]]; then
        log "INFO" "[configure_apt_option] Creando directorio de configuración: ${config_dir}"
        sudo mkdir -p "$config_dir" || { log "ERROR" "[configure_apt_option] No se pudo crear directorio ${config_dir}"; return 1; }
    fi
    if [[ ! -f "$config_file" ]]; then
        log "INFO" "[configure_apt_option] Archivo de configuración no encontrado: ${config_file}. Creándolo."
        sudo touch "$config_file" && sudo chmod 644 "$config_file" || { log "ERROR" "[configure_apt_option] No se pudo crear/establecer permisos en ${config_file}"; return 1; }
    fi

    # Escapar caracteres clave para grep (ERE) y sed (BRE/ERE)
    # Escapar: / & \ ] [ . * ^ $
    local escaped_key_grep escaped_key_sed escaped_value_sed desired_line
    escaped_key_grep=$(sed 's|[&/\]\[.*^$]|\\&|g' <<< "$key")
    escaped_key_sed=$(sed 's|[&/\]|\\&|g' <<< "$key")
    # Escapar el valor también es importante para sed
    escaped_value_sed=$(sed 's|[&/\]|\\&|g' <<< "$value")
    desired_line="${key} \"${value}\";" # Construir la línea deseada

    # Verificar si ya está configurado correctamente, capturando el código de salida de grep
    # Usamos sudo porque el archivo puede ser propiedad de root.
    log "DEBUG" "[configure_apt_option] Verificando si '${key}' ya es '${value}' en '${config_file}'..."
    sudo grep -Eq "^\s*${escaped_key_grep}\s*\"${value}\"\s*;" "$config_file" || grep_ec=$?

    # Analizar el código de salida de grep
    if [[ $grep_ec -eq 0 ]]; then
        # --- Caso 1: Éxito de grep (Código 0) ---
        # La línea exacta ya existe, no hacer nada.
        log "DEBUG" "[configure_apt_option] Opción '${key}' ya está configurada correctamente a '${value}' en ${config_file}"
        return 0 # Éxito, no se necesitaron cambios

    elif [[ $grep_ec -eq 1 ]]; then
        # --- Caso 2: Fallo de grep (Código 1) ---
        # La línea exacta no existe. Hay que modificar la existente o añadirla.
        log "INFO" "[configure_apt_option] Configurando '${key}' = '${value}' en ${config_file}..."

        # Comprobar si la *clave* existe (con cualquier valor) para saber si reemplazar o añadir
        # Usamos grep simple aquí (-q) solo para la comprobación de existencia de la clave
        if sudo grep -q "^\s*${escaped_key_grep}" "$config_file"; then
            # Clave existe, hay que reemplazar la línea completa
            log "DEBUG" "[configure_apt_option] Clave '${key}' encontrada, reemplazando línea..."
            tmp_sed_script="s/^\s*${escaped_key_sed}.*/${desired_line}/"
            # Usar sed -i con backup explícito para mayor seguridad
            if ! sudo sed -i.confiraspa.bak "$tmp_sed_script" "$config_file"; then
                log "ERROR" "[configure_apt_option] Fallo al modificar (sed) ${config_file} para clave '${key}'"
                # Intentar restaurar backup si sed falló
                if [[ -f "${config_file}.confiraspa.bak" ]]; then
                    sudo mv "${config_file}.confiraspa.bak" "$config_file" || log "ERROR" "[configure_apt_option] ¡FALLO AL RESTAURAR SED BACKUP!"
                fi
                return 1 # Fallo
            fi
            # Eliminar backup si sed tuvo éxito
            sudo rm -f "${config_file}.confiraspa.bak"
            log "DEBUG" "[configure_apt_option] Línea para '${key}' reemplazada con éxito."
            return 0 # Éxito

        else
            # Clave no existe, añadir la línea nueva al final
            log "DEBUG" "[configure_apt_option] Clave '${key}' no encontrada, añadiendo línea..."
            # Asegurar newline al final del archivo antes de añadir
            # Usar tail + comprobación para evitar problemas con archivos vacíos
            if [[ -s "$config_file" && "$(sudo tail -c1 "$config_file" 2>/dev/null)" != '' ]]; then
                log "DEBUG" "[configure_apt_option] Añadiendo newline faltante a ${config_file}..."
                if ! echo | sudo tee -a "$config_file" > /dev/null; then
                     log "ERROR" "[configure_apt_option] Fallo al añadir newline a ${config_file}"
                     return 1
                fi
            fi
            # Añadir la línea deseada
            log "DEBUG" "[configure_apt_option] Ejecutando: echo \"${desired_line}\" | sudo tee -a \"${config_file}\""
            if ! echo "$desired_line" | sudo tee -a "$config_file" > /dev/null; then
                 log "ERROR" "[configure_apt_option] Fallo al añadir línea '${desired_line}' a ${config_file}"
                 return 1
            fi
            log "DEBUG" "[configure_apt_option] Línea para '${key}' añadida con éxito."
            return 0 # Éxito
        fi

    else
        # --- Caso 3: Error de grep (Código > 1) ---
        # Error inesperado (archivo no legible, error de sintaxis regex, etc.)
        log "ERROR" "[configure_apt_option] Error inesperado (código ${grep_ec}) ejecutando grep en ${config_file} para la clave '${key}'"
        return 1 # Fallo
    fi
}

# Configura las opciones periódicas de APT
configure_periodic_updates() {
    log "INFO" "Configurando actualizaciones periódicas APT (${AUTO_UPGRADES_CONFIG})"
    local -a apt_settings=(
        "APT::Periodic::Update-Package-Lists 1"
        "APT::Periodic::Download-Upgradeable-Packages 1"
        "APT::Periodic::Unattended-Upgrade 1"
        "APT::Periodic::AutocleanInterval 7"
    )
    local setting key value all_err=0

    for setting in "${apt_settings[@]}"; do
        key="${setting% *}"
        value="${setting#* }"
        if ! configure_apt_option "$AUTO_UPGRADES_CONFIG" "$key" "$value"; then
            log "ERROR" "Fallo al configurar ${key} en ${AUTO_UPGRADES_CONFIG}"
            all_err=1  # Marcar fallo
        fi
    done
    return $all_err  # 0 si todo ok, 1 si hubo algún fallo
}

# Configura los orígenes y detalles de unattended-upgrades
configure_update_sources() {
    local distro_codename="$1"
    log "INFO" "Configurando detalles unattended-upgrades (${LOCAL_OVERRIDES_CONFIG})"

    # Contenido deseado (igual que antes, asegúrate que los orígenes son correctos para ti)
local desired_content=$(cat <<-EOF
// Configuración de unattended-upgrades gestionada por Confiraspa
// Este archivo anula configuraciones en 50unattended-upgrades

Unattended-Upgrade::Allowed-Origins {
    "Debian:${distro_codename}-security";
    "Debian:${distro_codename}-updates";
    "Raspbian:${distro_codename}";
    "Raspberry Pi Foundation:${distro_codename}";
};

//Unattended-Upgrade::Package-Blacklist { };
Unattended-Upgrade::Automatic-Reboot "false";
//Unattended-Upgrade::Automatic-Reboot-Time "04:00";
//Unattended-Upgrade::Mail "tu_email@dominio.com";
//Unattended-Upgrade::MailOnlyOnError "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
//Unattended-Upgrade::AutoCleanInterval "7"; // Controlado por APT::Periodic::AutocleanInterval
Unattended-Upgrade::Download-Upgradeable-Packages "true"; // Controlado por APT::Periodic...
//Unattended-Upgrade::Verbose "0";
EOF
)

    local temp_file current_content current_cleaned desired_cleaned
    temp_file=$(mktemp) || { log "ERROR" "No se pudo crear archivo temporal"; return 1; }
    trap 'rm -f "$temp_file"' RETURN

    # Crear archivo y directorio padre si no existen
    if [[ ! -d "$(dirname "$LOCAL_OVERRIDES_CONFIG")" ]]; then
        sudo mkdir -p "$(dirname "$LOCAL_OVERRIDES_CONFIG")" || { log "ERROR" "No se pudo crear dir para ${LOCAL_OVERRIDES_CONFIG}"; return 1; }
    fi
     if [[ ! -f "$LOCAL_OVERRIDES_CONFIG" ]]; then
        log "INFO" "Archivo ${LOCAL_OVERRIDES_CONFIG} no encontrado. Creándolo."
        sudo touch "$LOCAL_OVERRIDES_CONFIG" && sudo chmod 644 "$LOCAL_OVERRIDES_CONFIG" || { log "ERROR" "No se pudo crear/permisos ${LOCAL_OVERRIDES_CONFIG}"; return 1; }
    fi

    # Comparar contenido actual (limpio) con deseado (limpio)
    current_content=$(sudo cat "$LOCAL_OVERRIDES_CONFIG" 2>/dev/null)
    current_cleaned=$(echo "$current_content" | grep -v '^\s*//' | grep -v '^\s*$' | sort || true)
    desired_cleaned=$(echo "$desired_content" | grep -v '^\s*//' | grep -v '^\s*$' | sort || true)

    if [[ "$current_cleaned" == "$desired_cleaned" ]]; then
        log "INFO" "${LOCAL_OVERRIDES_CONFIG} ya está configurado correctamente."
        return 0
    fi

    log "INFO" "Actualizando ${LOCAL_OVERRIDES_CONFIG}..."
    # Crear backup ANTES de sobrescribir
    if ! create_backup "$LOCAL_OVERRIDES_CONFIG"; then
        log "ERROR" "Fallo al crear backup de ${LOCAL_OVERRIDES_CONFIG}. No se aplicarán cambios."
        return 1
    fi

    # Escribir contenido deseado
    echo "$desired_content" > "$temp_file" || { log "ERROR" "Fallo al escribir a temp file"; return 1; }

    # Mover el archivo temporal al destino final
    if ! sudo mv "$temp_file" "$LOCAL_OVERRIDES_CONFIG"; then
        log "ERROR" "Fallo al mover temp file a ${LOCAL_OVERRIDES_CONFIG}"
        # Intentar restaurar backup si falló la escritura
        restore_backup "$LOCAL_OVERRIDES_CONFIG" || log "ERROR" "¡FALLO AL RESTAURAR BACKUP de ${LOCAL_OVERRIDES_CONFIG}!"
        return 1
    fi
     # Asegurar permisos después de mover
    sudo chmod 644 "$LOCAL_OVERRIDES_CONFIG" || log "WARN" "Fallo al re-establecer permisos en ${LOCAL_OVERRIDES_CONFIG}"

    log "INFO" "${LOCAL_OVERRIDES_CONFIG} actualizado."
    return 0
}

# Ejecuta unattended-upgrade de forma segura
run_unattended_upgrade() {
    log "INFO" "Iniciando proceso de unattended-upgrade..."
    # Usar el log específico del script para esta ejecución,
    # unattended-upgrades tiene sus propios logs detallados en /var/log/unattended-upgrades/
    local script_log="${LOG_FILE:-/dev/null}" # Usar log del script si está definido

    log "INFO" "Paso 1/2: Ejecutando unattended-upgrade en modo dry-run..."
    # Añadir salida a nuestro log y también al log de unattended-upgrades
    if ! sudo unattended-upgrade --dry-run -d | tee -a "$script_log"; then
        log "WARN" "unattended-upgrade --dry-run finalizó con errores o no había nada que hacer. Ver logs arriba y en /var/log/unattended-upgrades/"
        # Decidir si continuar o no. Por seguridad, podríamos retornar 1 aquí.
        # return 1
        return 0 # O continuar e intentar la ejecución real
    fi

    log "INFO" "Paso 2/2: Ejecutando unattended-upgrade real..."
    if ! sudo unattended-upgrade -d | tee -a "$script_log"; then
        log "WARN" "unattended-upgrade finalizó con errores. Revisar logs arriba y en /var/log/unattended-upgrades/unattended-upgrades.log"
        return 1 # Indicar que hubo problemas
    fi

    log "INFO" "unattended-upgrade completado."
    return 0
}

# --- Ejecución Principal ---
main() {
    # --- Setup ---
    setup_error_handling
    check_root
    # setup_paths # No es necesario llamar explícitamente si utils.sh lo hace

    # --- Bloqueo ---
    log "DEBUG" "Adquiriendo lock: ${LOCK_FILE}"
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log "ERROR" "Script ya en ejecución (lock: ${LOCK_FILE}). Saliendo."
        exit 1
    fi
    trap 'flock -u 200; exit' EXIT HUP INT QUIT TERM # Liberar lock al salir

    log "INFO" "== Iniciando configuración de actualizaciones automáticas v3.1.1 =="

    # --- Dependencias ---
    install_dependencies "unattended-upgrades" "lsb-release" "apt-utils" || exit 1

    # --- Codename ---
    local distro_codename
    distro_codename=$(get_distro_codename) || exit 1
    log "INFO" "Codename distribución: ${distro_codename}"

    # --- Configuración ---
    # Configurar ejecución periódica vía APT
    configure_periodic_updates || { log "ERROR" "Fallo configurando APT periódico."; exit 1; }
    # Configurar qué/cómo actualizar vía unattended-upgrades
    configure_update_sources "$distro_codename" || { log "ERROR" "Fallo configurando fuentes/detalles unattended-upgrades."; exit 1; }

    # --- Ejecución Inicial (Opcional) ---
    log "INFO" "Realizando ciclo de actualización inicial (apt update + unattended-upgrade)..."
    log "INFO" "Actualizando lista de paquetes (apt update)..."
    if ! sudo apt update -qq; then
         log "WARN" "Fallo en 'apt update', se continuará pero unattended-upgrade podría no tener la última lista."
         # No salir, permitir que unattended-upgrade lo intente
    fi
    run_unattended_upgrade # Registrar advertencia si falla, pero no salir

    # --- Limpieza APT ---
    log "INFO" "Realizando limpieza final de APT (autoremove, clean)..."
    sudo apt autoremove -y -qq || log "WARN" "Comando 'apt autoremove' finalizó con error (o no había nada que quitar)."
    sudo apt clean -qq || log "WARN" "Comando 'apt clean' finalizó con error."

    # --- Conclusión ---
    log "SUCCESS" "Configuración de actualizaciones automáticas completada."
    log "INFO" "El sistema aplicará actualizaciones según ${LOCAL_OVERRIDES_CONFIG} y ${AUTO_UPGRADES_CONFIG}."
    log "INFO" "Verificar estado/logs en /var/log/unattended-upgrades/"

    # El trap se encarga de liberar el lock y salir
}

# --- Punto de Entrada ---
main # No necesita argumentos "$@"