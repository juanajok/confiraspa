# confiraspa
Este repositorio contiene el script confiraspi, que automatiza la reinstalación y configuración de una Raspberry Pi con diversas aplicaciones y servicios.

Descripción
===========
El script confiraspi es un script de shell que realiza varias tareas, incluyendo la actualización de la Raspberry Pi, configuración de IP estática, instalación y configuración de Samba, XRDP, Transmission, Mono, Sonarr y Webmin, y habilitar VNC. El objetivo del proyecto es facilitar la configuración de una Raspberry Pi para su uso en distintos escenarios.
#Samba: Permite compartir archivos y directorios a través de una red local.
#XRDP: Habilita el acceso remoto al escritorio de la Raspberry Pi.
#Transmission: Cliente de torrent para descargar y compartir archivos.
#Mono: Entorno de desarrollo para ejecutar aplicaciones basadas en .NET.
#Sonarr: Gestiona automáticamente tus series de TV y descarga nuevos episodios.
#Webmin: Herramienta de administración de sistemas basada en web para Linux.
#VNC: Permite el control remoto gráfico de una Raspberry Pi.
#Plex: Servidor de medios para organizar y transmitir películas, series de TV y música.
#Bazarr: Permite la descarga automática de subtítulos para tus series y películas.
#aMule: Cliente P2P para compartir archivos a través de la red eD2k y Kademlia.

Requisitos previos
Asegúrese de tener una Raspberry Pi con una distribución basada en Debian (por ejemplo, Raspberry Pi OS) y acceso a una terminal o línea de comandos en la Raspberry Pi.


Uso
====
1)  Clone este repositorio en su Raspberry Pi (preferiblemente en /opt): 

sudo mkdir -p /opt/confiraspa

sudo git clone https://github.com/juanajok/confiraspa /opt/confiraspa

2)  Navegue hasta el directorio del repositorio clonado:
 
cd /opt/confiraspa

3)  Asegúrese de que el script confiraspi sea ejecutable:

sudo chmod +x confiraspi_v3.0.sh

4)  Edite el archivo ip_config.json en el directorio del repositorio clonado, con la siguiente estructura:

{
  "interface": "eth0",
  "ip_address": "192.168.1.100/24",
  "routers": "192.168.1.1",
  "domain_name_servers": "8.8.8.8 8.8.4.4"
}

Ajuste los valores de interface, ip_address, routers y domain_name_servers según su configuración de red.

4)  Edita también el fichero credenciales.json:
{
       "password": "raspberry"
}

La aplicación aMule heredará el usuario con que ejecutes el script y la contraseña de ese json. (Recomendable editar el json justo antes de la ejecución y borrarlo o modificarlo tras la misma.)

5) Edita el fichero puntos_de_montaje.jso. Añade los puntos de montaje de los discos duros asociados

6)  Ejecute el script:

sudo bash ./confiraspi_v3.0.sh

Siga las instrucciones en pantalla y espere a que se complete la ejecución del script.


Dependencias
============
El script confiraspi no tiene dependencias adicionales, pero instalará y configurará varios paquetes y servicios en su Raspberry Pi, como se mencionó anteriormente en la descripción.


Contribuciones
==============
Las contribuciones son bienvenidas. Siéntase libre de abrir issues o enviar pull requests para mejorar el script o agregar nuevas funciones.


Licencia
========
Este proyecto está licenciado bajo la Licencia GNU General Public License v3.0. Para más información, consulte el archivo LICENSE en el repositorio.
