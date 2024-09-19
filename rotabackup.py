#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Script: backup_cleanup.py
Descripción: Este script elimina las versiones antiguas de archivos de backup,
             manteniendo solo las últimas versiones especificadas para cada aplicación.
Autor: [Tu Nombre]
Fecha de creación: 24/04/2023
Instrucciones:
    1. Asegúrate de que las rutas de las carpetas de backup estén en un archivo JSON
       llamado "app_backup_paths.json" ubicado en '/configs' con el siguiente formato:
       {
           "app_paths": [
               {
                   "path": "/ruta/al/backup/app1",
                   "num_copies_to_keep": 3
               },
               {
                   "path": "/ruta/al/backup/app2",
                   "num_copies_to_keep": 3
               }
           ]
       }
    2. Ejecuta el script con el comando 'python3 backup_cleanup.py' o dale permisos
       de ejecución y ejecútalo directamente como un ejecutable en sistemas Unix/Linux.
"""

import os
import glob
import json
import logging
from pathlib import Path
from datetime import datetime

# Configuración del logger
LOG_FILE = 'backup_cleanup.log'
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] [%(filename)s]: %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Lee las rutas de las carpetas de backup de las aplicaciones desde el archivo JSON
def read_app_paths(json_file):
    try:
        with open(json_file, "r") as file:
            data = json.load(file)
            return data["app_paths"]
    except FileNotFoundError:
        logger.error(f"El archivo de configuración '{json_file}' no se encontró.")
        exit(1)
    except json.JSONDecodeError as e:
        logger.error(f"Error al parsear el archivo JSON: {e}")
        exit(1)

# Encuentra los archivos en la carpeta y devuelve los más recientes según su fecha de modificación
def get_latest_backups(folder, num_copies_to_keep):
    all_files = sorted(
        glob.glob(os.path.join(folder, "*")),
        key=os.path.getmtime,
        reverse=True
    )
    return all_files[:num_copies_to_keep]

# Elimina todos los archivos que no estén en la lista latest_backups si aún existen
def remove_old_backups(folder, latest_backups):
    for file in glob.glob(os.path.join(folder, "*")):
        if file not in latest_backups and os.path.isfile(file):
            try:
                os.remove(file)
                logger.info(f"Eliminado: {file}")
            except Exception as e:
                logger.error(f"Error al eliminar '{file}': {e}")

def main():
    # Ruta al archivo de configuración
    CONFIG_DIR = "/configs"
    CONFIG_FILE = os.path.join(CONFIG_DIR, "app_backup_paths.json")

    app_paths = read_app_paths(CONFIG_FILE)

    for app_config in app_paths:
        app_path = app_config.get("path")
        num_copies_to_keep = app_config.get("num_copies_to_keep", 3)

        if not app_path:
            logger.error("No se especificó la ruta 'path' en la configuración.")
            continue

        folder = Path(app_path)

        if not folder.exists():
            logger.info(f"La ruta '{app_path}' no existe. Creando la carpeta.")
            try:
                folder.mkdir(parents=True, exist_ok=True)
            except Exception as e:
                logger.error(f"No se pudo crear la carpeta '{app_path}': {e}")
                continue

        if folder.is_dir():
            latest_backups = get_latest_backups(app_path, num_copies_to_keep)
            remove_old_backups(app_path, latest_backups)
        else:
            logger.error(f"La ruta '{app_path}' no es un directorio. Comprueba las rutas de las aplicaciones.")

if __name__ == "__main__":
    main()
