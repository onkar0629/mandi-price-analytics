"""
extract_mandi_data.py

Pulls records from the data.gov.in "Current Daily Price of Various
Commodities from Various Markets (Mandi)" API and saves them locally
as a CSV, partitioned by today's date.

Resource: Current Daily Price of Various Commodities from Various Markets (Mandi)
Resource ID: 9ef84268-d588-465a-a308-a864a43d0070

Usage:
    python extract_mandi_data.py
    python extract_mandi_data.py --limit 500 --out-dir ./data
"""

import argparse
import os
import sys
import time
from datetime import datetime

import pandas as pd
import requests
from dotenv import load_dotenv

load_dotenv()

RESOURCE_ID = "9ef84268-d588-465a-a308-a864a43d0070"
BASE_URL = f"https://api.data.gov.in/resource/{RESOURCE_ID}"

# Columns we expect back from the API, in a sensible order for the CSV
COLUMNS = [
    "state",
    "district",
    "market",
    "commodity",
    "variety",
    "grade",
    "arrival_date",
    "min_price",
    "max_price",
    "modal_price",
]


def get_api_key() -> str:
    api_key = os.getenv("MANDI_API_KEY")
    if not api_key:
        sys.exit(
            "ERROR: MANDI_API_KEY not found. Add it to a .env file:\n"
            "  MANDI_API_KEY=your_key_here"
        )
    return api_key


def fetch_page(api_key: str, offset: int, limit: int, max_retries: int = 3) -> dict:
    """Fetch a single page of records from the API, with retry/backoff."""
    params = {
        "api-key": api_key,
        "format": "json",
        "offset": offset,
        "limit": limit,
    }
    headers = {
        "Accept": "application/json",
        # The API silently stalls requests using Python's default
        # User-Agent header; spoofing curl's UA avoids that.
        "User-Agent": "curl/8.1.2",
    }

    for attempt in range(1, max_retries + 1):
        try:
            resp = requests.get(BASE_URL, params=params, headers=headers, timeout=60)
            resp.raise_for_status()
            data = resp.json()
            if "error" in data:
                sys.exit(f"ERROR from API: {data['error']}")
            return data
        except (requests.RequestException, ValueError) as exc:
            wait = 2 ** attempt  # 2s, 4s, 8s
            print(f"  [warn] request failed ({exc}); retrying in {wait}s "
                  f"(attempt {attempt}/{max_retries})")
            time.sleep(wait)

    sys.exit(f"ERROR: failed to fetch offset={offset} after {max_retries} attempts")


def fetch_all_records(api_key: str, page_size: int = 500) -> list:
    """
    Paginate through the full result set for today's data.
    Stops once the API returns fewer records than requested (last page)
    or an empty records list.
    """
    all_records = []
    offset = 0

    # First call tells us the total record count
    first_page = fetch_page(api_key, offset=0, limit=page_size)
    total = int(first_page.get("total", 0))
    records = first_page.get("records", [])
    all_records.extend(records)
    print(f"  fetched {len(records)} / {total} records (offset {offset})")

    offset += page_size
    while offset < total:
        page = fetch_page(api_key, offset=offset, limit=page_size)
        records = page.get("records", [])
        if not records:
            break
        all_records.extend(records)
        print(f"  fetched {len(records)} / {total} records (offset {offset})")
        offset += page_size

    return all_records


def main():
    parser = argparse.ArgumentParser(description="Extract Mandi daily price data.")
    parser.add_argument("--limit", type=int, default=100,
                         help="Records per API page (default 100).")
    parser.add_argument("--out-dir", type=str, default="./data",
                         help="Local directory to save the CSV into.")
    args = parser.parse_args()

    api_key = get_api_key()

    print(f"Fetching Mandi price data (page size={args.limit})...")
    records = fetch_all_records(api_key, page_size=args.limit)

    if not records:
        print("No records returned. Exiting without writing a file.")
        sys.exit(0)

    df = pd.DataFrame(records)

    # Ensure consistent column set/order even if the API omits a field
    # for some rows
    for col in COLUMNS:
        if col not in df.columns:
            df[col] = None
    df = df[COLUMNS]

    # Convert arrival_date (DD/MM/YYYY) to a proper date type
    df["arrival_date"] = pd.to_datetime(
        df["arrival_date"], format="%d/%m/%Y", errors="coerce"
    ).dt.date

    # Price columns to numeric (in case of stray strings/nulls)
    for price_col in ["min_price", "max_price", "modal_price"]:
        df[price_col] = pd.to_numeric(df[price_col], errors="coerce")

    # Partitioned output path: data/year=YYYY/month=MM/day=DD/mandi_prices.csv
    today = datetime.now()
    partition_dir = os.path.join(
        args.out_dir,
        f"year={today.year}",
        f"month={today.month:02d}",
        f"day={today.day:02d}",
    )
    os.makedirs(partition_dir, exist_ok=True)
    out_path = os.path.join(partition_dir, "mandi_prices.csv")

    df.to_csv(out_path, index=False)
    print(f"\nSaved {len(df)} records to {out_path}")
    print(f"Columns: {list(df.columns)}")


if __name__ == "__main__":
    main()