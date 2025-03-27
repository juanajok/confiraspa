#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script Name: limpiar_descargas.py
Description: Este script verifica si los archivos descargados han sido movidos a sus respectivas bibliotecas de medios y, de ser así, elimina los archivos redundantes en el directorio de descargas, junto con sus archivos asociados. También limpia los directorios vacíos que puedan quedar después de la eliminación.

Author: Juan José Hipólito
Version: 1.0
Date: 2023-11-08
License: MIT License
Usage: Ejecutar el script manualmente o programarlo con cron para ejecución automática.
Dependencies:
    - Python 3.x
    - Módulos estándar de Python: os, json, hashlib, logging, shutil, pathlib

Notes:
    - Asegúrate de que el archivo 'directories.json' esté en el mismo directorio que este script y que contenga las rutas correctas.
    - El script utiliza hashing SHA256 para comparar archivos y garantizar que son idénticos.
"""

import os
import json
import hashlib
import logging
import shutil
from pathlib import Path

# Configurar el logger
logging.basicConfig(
    format='%(asctime)s %(levelname)s: %(message)s',
    level=logging.INFO,
    handlers=[
        logging.StreamHandler(),  # Muestra los mensajes en la consola
        logging.FileHandler('downloadclean.py')  # Guarda los mensajes en un archivo de log
    ]
)

logger = logging.getLogger(__name__)

def get_file_hash(file_path):
    """Calcula y devuelve el hash SHA256 de un archivo."""
    hasher = hashlib.sha256()
    try:
        with open(file_path, 'rb') as f:
            for chunk in iter(lambda: f.read(65536), b""):
                hasher.update(chunk)
        return hasher.hexdigest()
    except Exception as e:
        logger.error(f"Error al calcular el hash del archivo '{file_path}': {e}")
        return None

def find_matching_file(source_file, library_dirs):
    """Busca un archivo que coincida en las bibliotecas de medios."""
    source_hash = get_file_hash(source_file)
    if not source_hash:
        return False

    for library_dir in library_dirs:
        for root, _, files in os.walk(library_dir):
            for file in files:
                target_file = os.path.join(root, file)
                if os.path.getsize(source_file) != os.path.getsize(target_file):
                    continue
                target_hash = get_file_hash(target_file)
                if source_hash == target_hash:
                    logger.info(f"Archivo '{source_file}' coincide con '{target_file}'")
                    return True
    return False

def delete_associated_files(file_path):
    """Elimina archivos asociados como .nfo, subtítulos, etc."""
    directory = os.path.dirname(file_path)
    base_name = os.path.splitext(os.path.basename(file_path))[0]
    associated_extensions = ['.nfo', '.srt', '.sub', '.idx', '.txt', '.jpg', '.jpeg', '.png']

    for file in os.listdir(directory):
        if file.startswith(base_name):
            file_ext = os.path.splitext(file)[1].lower()
            if file_ext in associated_extensions:
                associated_file_path = os.path.join(directory, file)
                try:
                    os.remove(associated_file_path)
                    logger.info(f"Archivo asociado eliminado: '{associated_file_path}'")
                except Exception as e:
                    logger.error(f"Error al eliminar '{associated_file_path}': {e}")

def clean_empty_directories(root_dir):
    """Elimina directorios vacíos recursivamente."""
    for dirpath, dirnames, filenames in os.walk(root_dir, topdown=False):
        if not dirnames and not filenames:
            try:
                os.rmdir(dirpath)
                logger.info(f"Directorio vacío eliminado: '{dirpath}'")
            except Exception as e:
                logger.error(f"Error al eliminar directorio '{dirpath}': {e}")

def main():
    # Cargar directorios desde el archivo JSON
    config_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "configs", "directories.json")
    try:
        with open(config_file, 'r') as f:
            config = json.load(f)
    except Exception as e:
        logger.error(f"Error al cargar el archivo de configuración: {e}")
        return

    download_dir = config.get("download_dir")
    library_dirs = [
        config.get("series_dir"),
        config.get("movies_dir"),
        config.get("music_dir"),
        config.get("comics_dir")
    ]

    # Verificar que los directorios existen
    if not download_dir or not os.path.isdir(download_dir):
        logger.error(f"El directorio de descargas no es válido: '{download_dir}'")
        return

    library_dirs = [d for d in library_dirs if d and os.path.isdir(d)]
    if not library_dirs:
        logger.error("No se encontraron bibliotecas de medios válidas en la configuración.")
        return

    # Extensiones de archivos multimedia
    media_extensions = ['.mp4', '.mkv', '.avi', '.mp3', '.flac', '.epub', '.pdf', '.cbr', '.cbz']

    # Recorrer los archivos en el directorio de descargas
    for root, dirs, files in os.walk(download_dir):
        for file in files:
            file_path = os.path.join(root, file)
            file_ext = os.path.splitext(file)[1].lower()

            if file_ext in media_extensions:
                logger.info(f"Procesando archivo: '{file_path}'")
                if find_matching_file(file_path, library_dirs):
                    try:
                        os.remove(file_path)
                        logger.info(f"Archivo eliminado: '{file_path}'")
                        delete_associated_files(file_path)
                    except Exception as e:
                        logger.error(f"Error al eliminar '{file_path}': {e}")
                else:
                    logger.info(f"El archivo '{file_path}' no se encontró en las bibliotecas. No se eliminará.")
            else:
                logger.debug(f"Omitiendo archivo no multimedia: '{file_path}'")

    # Eliminar directorios vacíos
    clean_empty_directories(download_dir)

if __name__ == "__main__":
    main()