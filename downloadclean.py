"""
Script para procesar archivos descargados. 

Si un archivo ya existe en la biblioteca, el script lo elimina de la ubicación original en la carpeta de descargas.

Autor: [Juan José Hipólito]
Fecha: [8 May 2023]

Requerimientos:
    - Python 3.5 o superior
    - módulos de Python: os, shutil, json, hashlib, logging

Instrucciones de uso:
    - Editar el archivo 'directories.json' con los directorios correctos de descarga y bibliotecas de medios.
    - Ejecutar el script 'downloadclean.py'.

"""

import os
import shutil
import json
import hashlib
import logging

# Configurar el logger con niveles adicionales
logging.basicConfig(
    format='%(asctime)s %(levelname)s [%(filename)s:%(funcName)s]: %(message)s', 
    level=logging.INFO,
    handlers=[
        logging.StreamHandler(), #para que los mensajes del logger se muestren en la consola
        logging.FileHandler('log.txt') #para que los mensajes se guarden en un archivo de registro
    ]
)

logger = logging.getLogger()

# Configurar los niveles de los handlers
console_handler = logging.StreamHandler()
console_handler.setLevel(logging.INFO)
file_handler = logging.FileHandler('log.txt')
file_handler.setLevel(logging.WARNING)

# Agregar los handlers al logger
logger.addHandler(console_handler)
logger.addHandler(file_handler)


  
def get_hash(file_path):
    """
    Calcula y devuelve el hash MD5 de un archivo en bytes.
    
    Parámetros:
        - file_path (str): ruta al archivo que se va a calcular el hash.
        
    Devuelve:
        - str: el hash MD5 del archivo o None si no se puede abrir o leer el archivo.
    """
    hasher = hashlib.md5()
    try:
        with open(file_path, 'rb') as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hasher.update(chunk)
        return hasher.hexdigest()
    except Exception as e:
        logger.error(f"Error while reading file {file_path}: {e}")
        return None



def check_file_in_library(file_path, library_dir):
    """
    Comprueba si un archivo existe en una biblioteca de medios mediante su hash MD5.

    Parámetros:
        - file_path (str): ruta al archivo que se va a verificar.
        - library_dir (str): ruta al directorio de la biblioteca de medios.

    Devuelve:
        - bool: True si el archivo existe en la biblioteca, False en caso contrario.
    """
    file_size = os.path.getsize(file_path)
    logger.debug(f"Checking if file {file_path} with size {file_size} is in {library_dir}")
    for entry in os.scandir(library_dir):
        if entry.is_file() and entry.stat().st_size == file_size:
            file_hash = get_hash(file_path)
            if file_hash is not None:
                if get_hash(entry.path) == file_hash:
                    logger.info(f"File {file_path} found in {library_dir}")
                    return True
                else:
                    logger.debug(f"Hashes for file {file_path} and {entry.path} do not match")
            else:
                logger.debug(f"Could not calculate hash for file {file_path}")
        elif entry.is_dir():
            logger.debug(f"Checking directory {entry.path}")
            if check_file_in_library(file_path, entry.path):
                return True
    logger.debug(f"File {file_path} not found in {library_dir}")
    return False





def delete_file(file_path):
    """
    Borra un archivo.

    Args:
        - file_path (str): La ruta al archivo que se va a borrar.

    Returns:
        - (bool) True si el archivo se borró correctamente, False en caso contrario.
    """
    try:
        os.unlink(file_path)
        logger.info(f"Deleted file {file_path}")
        return True
    except FileNotFoundError:
        logger.warning(f"File {file_path} not found")
        return False
    except Exception as e:
        logger.error(f"Error deleting {file_path}: {e}")
        return False

    
def get_file_extension(file_path):
    """
    Obtiene la extensión de un archivo.

    Args:
    - file_path (str): La ruta al archivo.

    Returns:
    - (str) La extensión del archivo en minúsculas, incluyendo el punto inicial (por ejemplo, ".txt").
    """
    return os.path.splitext(file_path)[1].lower()

def find_files_recursively(directory, extensions):
    """
    Recursively finds all files with given extensions in a directory and its subdirectories.

    Parameters:
        - directory (str): path to the directory to search in.
        - extensions (list of str): list of file extensions to search for (including the dot).

    Returns:
        - list of str: list of file paths that match the given extensions.
    """
    matching_files = []

    try:
        entries = os.scandir(directory)
    except FileNotFoundError:
        logger.warning(f"Directory not found: {directory}")
        return matching_files
    except PermissionError:
        logger.warning(f"Permission denied for directory: {directory}")
        return matching_files

    for entry in entries:
        if os.path.isfile(entry):
            extension = get_file_extension(entry)
            if extension in extensions:
                matching_files.append(entry)
            else:
                logger.debug(f"Skipping file {entry} with extension {extension}")
        elif entry.is_dir():
            logger.debug(f"Recursing into directory {entry.path}")
            matching_files += find_files_recursively(entry.path, extensions)
        else:
            logger.debug(f"Skipping non-file/directory {entry}")

    return matching_files

def remove_empty_directories_recursively(top_directory):
    """
    Recursively removes all empty directories under the given top directory.

    Parameters:
        - top_directory (str): path to the top directory to search in.

    Returns:
        - None
    """
    for root, dirs, _ in os.walk(top_directory, topdown=False):
        for directory in dirs:
            directory_path = os.path.join(root, directory)
            if not os.listdir(directory_path): # Check if directory is empty
                os.rmdir(directory_path)
                print(f"Directorio vacío {directory_path} borrado")


def main():
    # Load directories from JSON
    config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "directories.json")
    with open(config_path, "r") as f:
        directories = json.load(f)

    download_dir = directories.get("download_dir")
    series_dir = directories.get("series_dir")
    movies_dir = directories.get("movies_dir")
    music_dir = directories.get("music_dir")

    # Check if all required directories are present in the JSON file
    if None in [download_dir, series_dir, movies_dir, music_dir]:
        logger.error("One or more directories are missing from directories.json. Please check the file and try again.")
        return

    # Define the list of file types and their associated information
    file_types = [
        ((".mp4", ".mkv", ".avi"), series_dir, "Series", "series"),
        ((".mp4", ".mkv", ".avi"), movies_dir, "Movies", "movies"),
        ((".mp3", ".flac", ".ogg"), music_dir, "Music", "music")
    ]

    # Get the file extensions for each file type
    extensions = {}
    for extensions_list, _, _, print_name in file_types:
        extensions[print_name] = [extension.lower() for extension in extensions_list]

    # Iterate over the file types and process the files
    for extensions, destination_dir, log_name, print_name in file_types:
        matching_files = find_files_recursively(download_dir, extensions)
        if matching_files:
            logger.info(f"Processing {len(matching_files)} {print_name} files")
            for file_path in matching_files:
                if check_file_in_library(file_path, destination_dir):
                    if delete_file(file_path):
                        logger.info(f"{file_path} deleted from {print_name} library")
                    else:
                        logger.warning(f"Failed to delete {file_path} from {print_name} library")
        else:
            logger.info(f"No {print_name} files found to process")

    # delete empty folders

    remove_empty_directories_recursively(download_dir)

    # Clean up logging handlers
    logger.handlers = []


if __name__ == '__main__':
    main()
