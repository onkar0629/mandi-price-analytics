"""
upload_to_adls.py

Uploads today's extracted Mandi price CSV (produced by extract_mandi_data.py)
into an Azure Data Lake Storage Gen2 container, preserving the same
partitioned path structure locally and remotely:

    local:  ./data/year=YYYY/month=MM/day=DD/mandi_prices.csv
    remote: raw/mandi/year=YYYY/month=MM/day=DD/mandi_prices.csv

Usage:
    python upload_to_adls.py
    python upload_to_adls.py --local-dir ./data --container raw
"""

import argparse
import os
import sys
from datetime import datetime

from azure.storage.filedatalake import DataLakeServiceClient
from dotenv import load_dotenv

load_dotenv()


def get_connection_string() -> str:
    conn_str = os.getenv("AZURE_STORAGE_CONNECTION_STRING")
    if not conn_str:
        sys.exit(
            "ERROR: AZURE_STORAGE_CONNECTION_STRING not found. "
            "Add it to your .env file."
        )
    return conn_str


def build_today_paths(local_dir: str):
    """
    Returns (local_file_path, remote_path) for today's partition,
    matching the structure extract_mandi_data.py writes to.
    """
    today = datetime.now()
    partition = f"year={today.year}/month={today.month:02d}/day={today.day:02d}"
    local_path = os.path.join(local_dir, partition, "mandi_prices.csv")
    remote_path = f"mandi/{partition}/mandi_prices.csv"
    return local_path, remote_path


def upload_file(conn_str: str, container: str, local_path: str, remote_path: str):
    if not os.path.exists(local_path):
        sys.exit(
            f"ERROR: local file not found: {local_path}\n"
            f"Run extract_mandi_data.py first to generate it."
        )

    service_client = DataLakeServiceClient.from_connection_string(conn_str)
    file_system_client = service_client.get_file_system_client(file_system=container)

    # Create any missing directories in the path (idempotent)
    directory_path = os.path.dirname(remote_path)
    directory_client = file_system_client.get_directory_client(directory_path)
    directory_client.create_directory()  # no-op if it already exists

    file_name = os.path.basename(remote_path)
    file_client = directory_client.get_file_client(file_name)

    with open(local_path, "rb") as f:
        data = f.read()

    file_client.upload_data(data, overwrite=True)
    print(f"Uploaded {local_path} -> {container}/{remote_path} "
          f"({len(data)} bytes)")


def main():
    parser = argparse.ArgumentParser(description="Upload Mandi CSV to Azure ADLS Gen2.")
    parser.add_argument("--local-dir", type=str, default="./data",
                         help="Local directory extract_mandi_data.py wrote to.")
    parser.add_argument("--container", type=str, default="raw",
                         help="ADLS Gen2 container (file system) name.")
    args = parser.parse_args()

    conn_str = get_connection_string()
    local_path, remote_path = build_today_paths(args.local_dir)

    print(f"Uploading {local_path} to container '{args.container}'...")
    upload_file(conn_str, args.container, local_path, remote_path)


if __name__ == "__main__":
    main()