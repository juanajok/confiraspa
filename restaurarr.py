#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Script Name: restore_apps.py
Description: Restaura aplicaciones desde backups usando archivos JSON de configuración.
Author: Juan José Hipólito
Version: 2.1.0
Date: 2023-08-07
License: GNU
Usage: Ejecuta el script manualmente o programa su ejecución en crontab.
Dependencies: Python 3, json, os, shutil, tarfile, zipfile, subprocess, time, logging.
Notes:
- Asegúrate de que las rutas de origen y destino estén montadas antes de ejecutar este script.
- Es recomendable reiniciar el sistema después de la restauración para que las aplicaciones reconozcan los cambios.
"""

import json
import os
import shutil
import tarfile
import zipfile
import subprocess
import time
import logging
from logging.handlers import RotatingFileHandler

# Configuración global
CONFIG_DIR = "/configs"
CONFIG_FILE = os.path.join(CONFIG_DIR, "restore_apps.json")
LOG_FILE = "restore_apps.log"
MAX_LOG_SIZE = 5 * 1024 * 1024  # 5 MB
BACKUP_ORIG_DIR_NAME = "backup_orig"

def setup_logging():
    """Configura el sistema de logging."""
    logger = logging.getLogger("RestoreApps")
    logger.setLevel(logging.INFO)

    # Crear handler para archivo de log con rotación
    handler = RotatingFileHandler(LOG_FILE, maxBytes=MAX_LOG_SIZE, backupCount=3)
    formatter = logging.Formatter(
        "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)

    # Añadir handler para la consola
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)

    return logger

def load_config(config_file):
    """Carga el contenido de un archivo JSON y lo devuelve como diccionario."""
    try:
        with open(config_file, 'r') as f:
            config = json.load(f)
            return config
    except FileNotFoundError:
        logger.error(f"No se pudo encontrar el archivo de configuración '{config_file}'.")
        raise
    except json.JSONDecodeError as e:
        logger.error(f"Error al parsear el archivo JSON: {e}")
        raise

def get_latest_backup(backup_dir, backup_ext):
    """Devuelve la ruta completa del archivo de backup más reciente."""
    if not os.path.exists(backup_dir):
        logger.error(f"El directorio de backup '{backup_dir}' no existe.")
        return None

    if backup_ext:
        backup_files = [
            f for f in os.listdir(backup_dir)
            if f.endswith(backup_ext) and os.path.isfile(os.path.join(backup_dir, f))
        ]
    else:
        backup_files = [
            f for f in os.listdir(backup_dir)
            if os.path.isfile(os.path.join(backup_dir, f))
        ]

    if not backup_files:
        logger.error(f"No se encontraron archivos de backup en '{backup_dir}'.")
        return None

    backup_files.sort(
        key=lambda f: os.path.getmtime(os.path.join(backup_dir, f)),
        reverse=True
    )
    latest_backup = os.path.join(backup_dir, backup_files[0])
    logger.info(f"Último backup encontrado: '{latest_backup}'.")
    return latest_backup

def stop_app(app):
    """Detiene el servicio de la aplicación."""
    logger.info(f"Deteniendo la aplicación '{app}'...")
    try:
        subprocess.run(
            ["systemctl", "stop", app],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        logger.info(f"La aplicación '{app}' ha sido detenida exitosamente.")
    except subprocess.CalledProcessError as e:
        logger.error(f"Error al detener la aplicación '{app}': {e.stderr.decode().strip()}")
        raise

def start_app(app):
    """Inicia el servicio de la aplicación."""
    logger.info(f"Iniciando la aplicación '{app}'...")
    try:
        subprocess.run(
            ["systemctl", "start", app],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        logger.info(f"La aplicación '{app}' ha sido iniciada exitosamente.")
    except subprocess.CalledProcessError as e:
        logger.error(f"Error al iniciar la aplicación '{app}': {e.stderr.decode().strip()}")
        raise

def backup_original_files(files, restore_dir, backup_orig_dir):
    """Realiza una copia de seguridad de los archivos originales."""
    if not os.path.exists(backup_orig_dir):
        os.makedirs(backup_orig_dir)
        logger.info(f"Directorio '{backup_orig_dir}' creado para el backup de archivos originales.")

    for file in files:
        src_path = os.path.join(restore_dir, file)
        dst_path = os.path.join(backup_orig_dir, file)
        if os.path.exists(src_path):
            os.makedirs(os.path.dirname(dst_path), exist_ok=True)
            shutil.copy2(src_path, dst_path)
            logger.info(f"Archivo '{src_path}' copiado a '{dst_path}'.")
        else:
            logger.warning(f"Archivo original '{src_path}' no encontrado; no se pudo hacer backup.")

def extract_backup(backup_file, backup_ext, files, restore_dir):
    """Extrae los archivos especificados desde el backup al directorio de restauración."""
    logger.info(f"Extrayendo archivos desde el backup '{backup_file}'...")
    if backup_ext == ".zip":
        with zipfile.ZipFile(backup_file, "r") as zf:
            for file in files:
                try:
                    zf.extract(file, restore_dir)
                    logger.info(f"Archivo '{file}' extraído exitosamente.")
                except KeyError:
                    logger.error(f"Archivo '{file}' no encontrado en el backup.")
                    raise
    elif backup_ext in [".tar", ".tar.gz", ".tgz"]:
        with tarfile.open(backup_file, "r:*") as tf:
            for file in files:
                try:
                    tf.extract(file, restore_dir)
                    logger.info(f"Archivo '{file}' extraído exitosamente.")
                except KeyError:
                    logger.error(f"Archivo '{file}' no encontrado en el backup.")
                    raise
    else:
        # Asumimos que el backup es un directorio o un archivo sin comprimir
        for file in files:
            src_path = os.path.join(backup_file, file)
            dst_path = os.path.join(restore_dir, file)
            if os.path.exists(src_path):
                os.makedirs(os.path.dirname(dst_path), exist_ok=True)
                shutil.copy2(src_path, dst_path)
                logger.info(f"Archivo '{src_path}' copiado a '{dst_path}'.")
            else:
                logger.warning(f"Archivo '{src_path}' no encontrado en el backup.")

def change_permissions(permissions, restore_dir):
    """Cambia los permisos de los archivos restaurados."""
    for file, perm in permissions.items():
        file_path = os.path.join(restore_dir, file)
        if os.path.exists(file_path):
            try:
                os.chmod(file_path, int(perm, 8))
                logger.info(f"Permisos de '{file_path}' cambiados a '{perm}'.")
            except Exception as e:
                logger.error(f"No se pudieron cambiar los permisos de '{file_path}': {e}")
                raise
        else:
            logger.warning(f"Archivo '{file_path}' no encontrado para cambiar permisos.")

def restore_app(app, app_config):
    """Restaura una aplicación según su configuración."""
    logger.info(f"--- Iniciando restauración de '{app}' ---")

    backup_dir = app_config.get("backup_dir")
    backup_ext = app_config.get("backup_ext")
    restore_dir = app_config.get("restore_dir")
    files = app_config.get("files_to_restore", [])
    permissions = app_config.get("file_permissions", {})

    # Validaciones
    if not all([backup_dir, restore_dir, files]):
        logger.error(f"Configuración incompleta para la aplicación '{app}'.")
        return

    # Asegurar que backup_ext comienza con '.'
    if backup_ext and not backup_ext.startswith('.'):
        backup_ext = f".{backup_ext}"

    # Detener la aplicación si no es 'rclone' (no es un servicio)
    if app.lower() != "rclone":
        try:
            stop_app(app)
        except Exception:
            logger.error(f"No se pudo detener la aplicación '{app}'. Continuando con la restauración.")
    else:
        logger.info(f"La aplicación '{app}' no es un servicio; no se requiere detener.")

    # Crear directorio de restauración si no existe
    os.makedirs(restore_dir, exist_ok=True)

    # Realizar backup de archivos originales
    backup_orig_dir = os.path.join(restore_dir, BACKUP_ORIG_DIR_NAME)
    backup_original_files(files, restore_dir, backup_orig_dir)

    # Obtener el último backup disponible
    backup_file = get_latest_backup(backup_dir, backup_ext)
    if not backup_file:
        logger.error(f"No se pudo encontrar un backup válido para '{app}'.")
        return

    # Restaurar archivos desde el backup
    try:
        extract_backup(backup_file, backup_ext, files, restore_dir)
    except Exception:
        logger.error(f"Error durante la extracción de archivos para '{app}'.")
        return

    # Cambiar permisos de archivos restaurados
    try:
        change_permissions(permissions, restore_dir)
    except Exception:
        logger.error(f"Error al cambiar permisos para '{app}'.")
        return

    # Iniciar la aplicación si no es 'rclone'
    if app.lower() != "rclone":
        try:
            start_app(app)
        except Exception:
            logger.error(f"No se pudo iniciar la aplicación '{app}' después de la restauración.")
            return
    else:
        logger.info(f"La aplicación '{app}' no es un servicio; no se requiere iniciar.")

    logger.info(f"Restauración de '{app}' completada exitosamente.")
    logger.info(f"--- Fin de restauración de '{app}' ---\n")

def main():
    """Función principal."""
    global logger
    logger = setup_logging()

    logger.info("Iniciando proceso de restauración de aplicaciones.")

    # Cargar configuración
    try:
        config = load_config(CONFIG_FILE)
    except Exception as e:
        logger.error(f"No se pudo cargar la configuración: {e}")
        return

    # Restaurar cada aplicación
    for app, app_config in config.items():
        try:
            restore_app(app, app_config)
        except Exception as e:
            logger.error(f"Error inesperado al restaurar '{app}': {e}")

    logger.info("Proceso de restauración completado.")
    logger.info("Es recomendable reiniciar el sistema para que los cambios surtan efecto.")

if __name__ == '__main__':
    main()
