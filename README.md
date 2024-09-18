Confiraspa:
Automatiza la reinstalación y configuración de una Raspberry Pi con diversas aplicaciones y servicios.

Índice
Descripción
Características
Requisitos previos
Instalación
Uso
Dependencias
Contribuciones
Licencia


Descripción
============
Confiraspa es un script de shell que automatiza la configuración de una Raspberry Pi, realizando tareas como la actualización del sistema, configuración de IP estática e instalación y configuración de varios servicios y aplicaciones. El objetivo del proyecto es facilitar y agilizar el proceso de preparación de una Raspberry Pi para diversos usos.

Características
===============

El script realiza las siguientes tareas:

Actualización del sistema: Mantiene la Raspberry Pi actualizada.

Configuración de IP estática: Establece una dirección IP fija para la Raspberry Pi.

Instalación y configuración de servicios y aplicaciones, incluyendo:

Samba: Permite compartir archivos y directorios a través de una red local.
XRDP: Habilita el acceso remoto al escritorio de la Raspberry Pi.
Transmission: Cliente BitTorrent para descargar y compartir archivos.
Mono: Entorno de desarrollo para ejecutar aplicaciones basadas en .NET.
Sonarr: Gestiona automáticamente tus series de TV y descarga nuevos episodios.
Webmin: Herramienta de administración de sistemas basada en web para Linux.
VNC: Permite el control remoto gráfico de la Raspberry Pi.
Plex: Servidor multimedia para organizar y transmitir películas, series de TV y música.
Bazarr: Descarga automática de subtítulos para tus series y películas.
aMule: Cliente P2P para compartir archivos a través de las redes eD2k y Kademlia.
Rclone: Sincroniza archivos y directorios con servicios de almacenamiento en la nube.

Requisitos previos
==================
Hardware: Una Raspberry Pi con una distribución basada en Debian (por ejemplo, Raspberry Pi OS).
Acceso: Acceso a una terminal o línea de comandos en la Raspberry Pi.
Conexión a Internet: Para descargar paquetes y dependencias.

Instalación
===========
Clonar el repositorio

Clone este repositorio en su Raspberry Pi (recomendado en /opt/confiraspa):


sudo mkdir -p /opt/confiraspa
sudo git clone https://github.com/juanajok/confiraspa /opt/confiraspa
Navegar al directorio del repositorio


cd /opt/confiraspa
Asegurar permisos de ejecución

Haga que el script confiraspi.sh sea ejecutable:


sudo chmod +x confiraspi.sh
Uso
Antes de ejecutar el script, es necesario configurar algunos archivos:

Editar archivos de configuración

Configuración de red: Edite el archivo ip_config.json en el directorio del repositorio:


{
  "interface": "eth0",
  "ip_address": "192.168.1.100/24",
  "routers": "192.168.1.1",
  "domain_name_servers": "8.8.8.8 8.8.4.4"
}
Ajuste los valores según su configuración de red.

Credenciales: Edite el archivo credenciales.json:


{
  "password": "tu_contraseña"
}


Nota: La aplicación aMule utilizará el usuario con el que ejecute el script y la contraseña proporcionada en este archivo. Es recomendable editar este archivo justo antes de la ejecución y eliminarlo o modificarlo después por motivos de seguridad.

Puntos de montaje: Edite el archivo puntos_de_montaje.json y añada los puntos de montaje de los discos duros asociados.

Ejecutar el script


sudo ./confiraspi.sh
Siga las instrucciones en pantalla y espere a que se complete la ejecución del script.

Dependencias
===============

El script confiraspi.sh se encargará de instalar y configurar los paquetes y servicios necesarios en su Raspberry Pi, como se mencionó en la sección de características.

Nota: Asegúrese de que su sistema tiene instalados los paquetes git y jq. Si no los tiene, puede instalarlos con:


sudo apt-get update
sudo apt-get install -y git jq
Contribuciones
Las contribuciones son bienvenidas. Siéntase libre de abrir issues o enviar pull requests para mejorar el script o agregar nuevas funciones.

Licencia
Este proyecto está licenciado bajo la Licencia GNU General Public License v3.0. Para más información, consulte el archivo LICENSE en el repositorio.