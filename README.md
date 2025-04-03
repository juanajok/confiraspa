# Confiraspa 🚀

**Automatiza la instalación, configuración y gestión de servicios en tu Raspberry Pi.**

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
<!-- Opcional: Añadir otros badges si aplican (ej. versión, build status) -->

---

## Índice

*   [Descripción](#descripción-)
*   [Filosofía y Objetivos](#filosofía-y-objetivos-)
*   [Características Principales](#características-principales-)
*   [Arquitectura del Proyecto](#arquitectura-del-proyecto-)
*   [Software Instalado](#software-instalado-)
*   [Requisitos Previos](#requisitos-previos-)
*   [Instalación](#instalación-)
*   [Configuración](#configuración-️)
*   [Uso](#uso-)
*   [Contribuciones](#contribuciones-)
*   [Licencia](#licencia-)

---

## Descripción 📖

Confiraspa es un conjunto de scripts de shell diseñados para **automatizar la configuración inicial y la instalación de servicios comunes en una Raspberry Pi** (especialmente con Raspberry Pi OS). Simplifica drásticamente el proceso de convertir una instalación limpia del sistema operativo en un servidor doméstico funcional (por ejemplo, para gestión multimedia, descargas, compartición de archivos y administración remota).

El proyecto nace de la necesidad de tener un método **repetible, consistente y rápido** para configurar una Raspberry Pi, evitando tareas manuales tediosas y propensas a errores.

---

## Filosofía y Objetivos 🎯

*   **Automatización:** Reducir al mínimo la intervención manual.
*   **Idempotencia:** Poder ejecutar los scripts múltiples veces sin efectos secundarios negativos (los servicios ya instalados no se reinstalan innecesariamente).
*   **Modularidad:** Scripts separados para cada aplicación principal, facilitando el mantenimiento y la personalización.
*   **Configurabilidad:** Uso de archivos de configuración externos (JSON) para parámetros clave (red, credenciales, usuarios, montajes).
*   **Buenas Prácticas:** Seguir principios de scripting robusto (manejo de errores, logging, uso de librerías comunes).
*   **Facilidad de Uso:** Un script principal orquesta la ejecución, pero los scripts individuales pueden usarse para depuración o instalación selectiva.

---

## Características Principales ✨

*   **Actualización del Sistema:** Ejecuta `apt update` y `apt upgrade` iniciales.
*   **Configuración de Red:** Establece una dirección IP estática basada en `ip_config.json`.
*   **Instalación y Configuración Modular de Servicios:**
    *   Instala dependencias necesarias del sistema.
    *   Crea usuarios y grupos de sistema si es necesario (configurable).
    *   Configura directorios de datos y permisos.
    *   Descarga/instala las aplicaciones.
    *   Configura y habilita servicios `systemd` para cada aplicación.
    *   Utiliza entornos virtuales Python (`venv`) cuando es apropiado (ej. Bazarr).
*   **Logging:** Registros detallados en `logs/` para el script principal y cada sub-script.
*   **Utilidades Compartidas:** Una librería (`lib/utils.sh`) proporciona funciones comunes para logging, manejo de errores, instalación de dependencias, etc.

---

## Arquitectura del Proyecto 🏗️

Confiraspa está estructurado de la siguiente manera:

*   `/opt/confiraspa/` (Directorio raíz recomendado)
    *   `confiraspi_v5.sh`: Script principal que orquesta la ejecución de otros scripts.
    *   `scripts/`: Contiene los scripts de instalación individuales para cada aplicación (ej. `install_sonarr.sh`, `install_bazarr.sh`).
    *   `lib/`: Contiene librerías de shell compartidas.
        *   `utils.sh`: Funciones comunes de utilidad (logging, dependencias, etc.).
    *   `configs/`: **Archivos de configuración que DEBES editar.**
        *   `ip_config.json`: Configuración de red estática.
        *   `credenciales.json`: Contraseñas (¡manejar con cuidado!).
        *   `arr_user.json`: Usuario y grupo para ejecutar los servicios \*Arr (Sonarr, Radarr, Bazarr...).
        *   `puntos_de_montaje.json`: Puntos de montaje para discos externos.
    *   `logs/`: Directorio donde se generan los archivos de log.
    *   `README.md`: Este archivo.
    *   `LICENSE`: Licencia del proyecto.

---

## Software Instalado 📦

Confiraspa puede instalar y configurar (según esté implementado en `confiraspi_v5.sh`) los siguientes paquetes y servicios:

*   **Compartición de Archivos:**
    *   `samba`: Para compartir archivos en la red local (SMB/CIFS).
*   **Acceso Remoto:**
    *   `xrdp`: Servidor RDP para acceso gráfico remoto.
    *   *VNC* (Configuración manual o a través de otro script puede ser necesaria dependiendo del método).
*   **Descargas:**
    *   `transmission-daemon`: Cliente BitTorrent ligero.
    *   `amule-daemon`: Cliente eD2k/Kademlia.
*   **Gestión Multimedia (\*Arr Suite):**
    *   `mono-runtime`: Dependencia para Sonarr v3 (Sonarr v4 usa .NET).
    *   `dotnet-sdk` / `dotnet-runtime`: Dependencia para aplicaciones .NET (como Sonarr v4+). *(Nota: La instalación de .NET puede variar)*.
    *   `sonarr`: Gestión y descarga automatizada de series de TV.
    *   `radarr`: Gestión y descarga automatizada de películas. *(No mencionado explícitamente en el original, pero es hermano de Sonarr/Bazarr)*
    *   `bazarr`: Gestión y descarga automatizada de subtítulos.
    *   `plexmediaserver`: Servidor multimedia para organizar y transmitir contenido.
*   **Administración:**
    *   `webmin`: Interfaz web para administración del sistema.
*   **Utilidades:**
    *   `rclone`: Sincronización con servicios de almacenamiento en la nube.
    *   `jq`: Procesador JSON (usado por los scripts).
    *   `git`: Sistema de control de versiones (usado para clonar Confiraspa y algunas apps).
    *   Otras dependencias necesarias para las aplicaciones anteriores (`curl`, `wget`, `python3-pip`, `python3-venv`, librerías de desarrollo, etc.).

---

## Requisitos Previos 📝

*   **Hardware:** Una Raspberry Pi (probado principalmente en RPi 4/5, pero debería funcionar en otras con suficiente RAM/CPU).
*   **Sistema Operativo:** Raspberry Pi OS (basado en Debian Bullseye o Bookworm). Otras distribuciones basadas en Debian *podrían* funcionar con ajustes.
*   **Acceso:** Acceso a la terminal con privilegios `sudo`.
*   **Conexión a Internet:** Necesaria para descargar el repositorio, paquetes del sistema y aplicaciones.
*   **Herramientas Esenciales:** **Debes** tener `git` y `jq` instalados *antes* de ejecutar Confiraspa. Instálalos si no los tienes:
    ```bash
    sudo apt-get update
    sudo apt-get install -y git jq
    ```

---

## Instalación 🛠️

1.  **Clonar el Repositorio:** Se recomienda usar `/opt/confiraspa`.
    ```bash
    # Crear directorio padre (si no existe)
    sudo mkdir -p /opt/confiraspa
    # Clonar
    sudo git clone https://github.com/juanajok/confiraspa /opt/confiraspa
    ```
2.  **Navegar al Directorio:**
    ```bash
    cd /opt/confiraspa
    ```
3.  **Verificar Permisos (Opcional):** `git clone` normalmente preserva los permisos, pero puedes asegurarte de que los scripts sean ejecutables si es necesario (aunque se ejecutan con `bash`):
    ```bash
    # Ejemplo: asegurar permisos en el script principal
    # sudo chmod +x confiraspi_v5.sh
    # sudo chmod +x scripts/*.sh
    ```

---

## Configuración ✏️

**¡Este es el paso más importante antes de ejecutar!** Debes editar los archivos JSON dentro del directorio `configs/`.

1.  **Configuración de Red (`configs/ip_config.json`):**
    Define la IP estática deseada para tu Raspberry Pi.
    ```json
    {
      "interface": "eth0",  # O wlan0 para WiFi
      "ip_address": "192.168.1.100/24", # IP deseada y máscara (formato CIDR)
      "routers": "192.168.1.1", # IP de tu puerta de enlace (router)
      "domain_name_servers": "8.8.8.8 8.8.4.4" # Servidores DNS (separados por espacio)
    }
    ```
2.  **Credenciales (`configs/credenciales.json`):**
    Contiene contraseñas usadas por algunas aplicaciones.
    ```json
    {
      "password": "tu_contraseña_segura"
    }
    ```
    *   **⚠️ ¡ADVERTENCIA DE SEGURIDAD! ⚠️** Este archivo contiene contraseñas en texto plano.
        *   **Edítalo justo antes de ejecutar el script.**
        *   **Utiliza contraseñas fuertes y únicas.**
        *   **Considera eliminar o vaciar este archivo después de la ejecución.** (Algunas aplicaciones podrían necesitar la contraseña de nuevo si se reconfiguran).
    *   Actualmente, se menciona que aMule usa esta contraseña y el usuario que ejecuta el script. Verifica si otras aplicaciones también la usan.
3.  **Usuario/Grupo \*Arr (`configs/arr_user.json`):**
    Define el usuario y grupo bajo el cual se ejecutarán Sonarr, Radarr, Bazarr, etc. Esto es importante para la gestión de permisos de archivos multimedia.
    ```json
    {
      "user": "pi",  # Usuario deseado (ej. 'pi' o un usuario dedicado como 'media')
      "group": "pi"  # Grupo deseado (ej. 'pi' o 'media')
    }
    ```
    *   El script intentará crear este usuario/grupo como usuario de sistema (`--system`) si no existen.
    *   Asegúrate de que este usuario/grupo tenga los permisos adecuados en tus directorios de descargas y multimedia.
4.  **Puntos de Montaje (`configs/puntos_de_montaje.json`):**
    Define cómo montar discos duros externos. Adapta la estructura según necesite el script que lo use (ej. para configurar Samba o las rutas en \*Arr). *(El formato exacto puede depender de cómo lo use `confiraspi_v5.sh`)*.
    ```json
    // Ejemplo de posible estructura (¡Verifica cómo lo usa tu script!)
    [
      {
        "device": "/dev/sda1",
        "mount_point": "/mnt/disco1",
        "filesystem": "ext4", // o ntfs, exfat, etc.
        "options": "defaults,nofail"
      },
      {
        "device": "/dev/disk/by-uuid/TU_UUID_AQUI", // Método más robusto
        "mount_point": "/mnt/disco2",
        "filesystem": "ext4",
        "options": "defaults,nofail"
      }
    ]
    ```

---

## Uso ▶️

1.  **Asegúrate de haber editado los archivos en `configs/` correctamente.**
2.  **Ejecuta el script principal como root:**
    ```bash
    cd /opt/confiraspa
    sudo bash ./confiraspi_v5.sh
    ```
3.  **Sigue las Instrucciones:** El script puede pedir confirmaciones o mostrar información durante la ejecución.
4.  **Ten Paciencia:** La ejecución completa puede tardar bastante tiempo, especialmente la primera vez, debido a las actualizaciones del sistema y la descarga/instalación de paquetes.
5.  **Revisa los Logs:** Si algo falla, revisa los archivos en el directorio `logs/` para obtener detalles.

*   **Ejecución de Scripts Individuales:** Para depuración o instalación selectiva, puedes ejecutar los scripts dentro del directorio `scripts/` (también generalmente con `sudo bash scripts/nombre_script.sh`), pero ten en cuenta que pueden depender de configuraciones o pasos realizados por el script principal o por `utils.sh`.

---

## Contribuciones 🤝

¡Las contribuciones son bienvenidas! Si encuentras errores, tienes sugerencias de mejora o quieres añadir soporte para nuevas aplicaciones:

1.  **Revisa los Issues:** Mira si tu idea o problema ya está reportado.
2.  **Abre un Issue:** Describe claramente el problema o la propuesta de mejora.
3.  **Crea un Fork:** Haz un fork del repositorio.
4.  **Crea una Rama:** `git checkout -b mi-nueva-feature`
5.  **Haz tus Cambios:** Intenta seguir el estilo y la estructura existentes (modularidad, uso de `utils.sh`).
6.  **Haz Commit:** `git commit -m 'Añade nueva feature'`
7.  **Haz Push:** `git push origin mi-nueva-feature`
8.  **Abre un Pull Request:** Describe tus cambios detalladamente.

---

## Licencia 📜

Este proyecto está licenciado bajo la Licencia Pública General GNU v3.0. Consulta el archivo `LICENSE` para más detalles.