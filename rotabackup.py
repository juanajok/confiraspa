#!/usr/bin/env python3

"""
Script: backup_cleanup.py
Descripción: Este script elimina las versiones antiguas de archivos de backup, 
             manteniendo solo las tres últimas versiones de cada aplicación.
Autor: Tu nombre
Fecha de creación: 24/04/2023
Instrucciones: 
    1. Asegúrate de que las rutas de las carpetas de backup estén en un archivo JSON
       llamado "app_backup_paths.json" con el siguiente formato:
       {
           "app_paths": [
               "/ruta/al/backup/app1",
               "/ruta/al/backup/app2",
               ...
           ]
       }
    2. Ejecuta el script con el comando 'python3 backup_cleanup.py' o dale permisos
       de ejecución y ejecútalo directamente como un ejecutable en sistemas Unix/Linux.
"""

import os
import glob
import json
from pathlib import Path
from datetime import datetime

# Lee las rutas de las carpetas de backup de las aplicaciones desde el archivo JSON
def read_app_paths(json_file):
    with open(json_file, "r") as file:
        data = json.load(file)
        return data["app_paths"]

# Encuentra los archivos en la carpeta y devuelve los 3 más recientes según su fecha de modificación
def get_latest_backups(folder, num_copies_to_keep):
    all_files = glob.glob(os.path.join(folder, "*"))
    all_files.sort(key=os.path.getmtime, reverse=True)
    return all_files[:num_copies_to_keep]

# Elimina todos los archivos que no estén en la lista latest_backups si aún existen
def remove_old_backups(folder, latest_backups):
    for file in glob.glob(os.path.join(folder, "*")):
        if file not in latest_backups and os.path.exists(file):
            os.remove(file)
            print(f"[{datetime.now()}] [INFO] [{os.path.basename(__file__)}] Eliminado: {file}")

def main():
    app_paths = read_app_paths("app_backup_paths.json")  # Especifica el nombre del archivo JSON aquí

    for app_config in app_paths:
        app_path = app_config["path"]
        num_copies_to_keep = app_config["num_copies_to_keep"]
        folder = Path(app_path)
        
        if not folder.exists():
            print(f"[{datetime.now()}] [INFO] [{os.path.basename(__file__)}] La ruta '{app_path}' no existe. Creando la carpeta.")
            folder.mkdir(parents=True, exist_ok=True)

        if folder.is_dir():
            latest_backups = get_latest_backups(app_path, num_copies_to_keep)
            remove_old_backups(app_path, latest_backups)
        else:
            print(f"[{datetime.now()}] [ERROR] [{os.path.basename(__file__)}] La ruta '{app_path}' no es un directorio. Comprueba las rutas de las aplicaciones.")

if __name__ == "__main__":
    main()