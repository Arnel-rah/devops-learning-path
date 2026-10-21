import requests
import urllib3
from urllib3.util import connection

TARGET_IP = "104.21.52.197"
_orig_create_connection = connection.create_connection

def patched_create_connection(address, *args, **kwargs):
    host, port = address
    if host == "sadiarnel.me":
        return _orig_create_connection((TARGET_IP, port), *args, **kwargs)
    return _orig_create_connection(address, *args, **kwargs)

connection.create_connection = patched_create_connection

URL = "https://sadiarnel.me"

print(f"Tentative de connexion à {URL} (forcée sur l'IP {TARGET_IP})...")

try:
    response = requests.get(URL, timeout=3)
    print(f"Succès ! Le serveur a répondu avec le code : {response.status_code}")
except requests.exceptions.Timeout:
    print("ERREUR : Le serveur a mis trop de temps à répondre (Timeout de 3s dépassé).")
    print("Action DevOps : Activation du mode dégradé (utilisation du cache local).")
except requests.exceptions.RequestException as e:
    print(f"ERREUR RÉSEAU : Impossible de joindre le serveur. Détails : {e}")
