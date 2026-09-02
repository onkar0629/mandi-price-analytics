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

# All Indian states and union territories. Filtering per-state keeps each
# individual query's result window safely under the API's internal ~10,000
# record cap (a backend Elasticsearch limit) -- a single flat query for a
# busy day can exceed that and silently truncate.
#
# Note: this dataset uses "Keralam" rather than "Kerala" -- confirmed from
# real API responses. If a state/UT below doesn't match the source's exact
# spelling, that filter just returns 0 records for it (harmless), but it's
# worth spot-checking totals if a state you expect data for shows 0.
STATES = [
    "Andhra Pradesh", "Arunachal Pradesh", "Assam", "Bihar", "Chhattisgarh",
    "Goa", "Gujarat", "Haryana", "Himachal Pradesh", "Jharkhand", "Karnataka",
    "Keralam", "Madhya Pradesh", "Maharashtra", "Manipur", "Meghalaya",
    "Mizoram", "Nagaland", "Odisha", "Punjab", "Rajasthan", "Sikkim",
    "Tamil Nadu", "Telangana", "Tripura", "Uttar Pradesh", "Uttarakhand",
    "West Bengal",
    # Union territories
    "Andaman and Nicobar", "Chandigarh",
    "Dadra and Nagar Haveli and Daman and Diu", "Delhi", "Jammu and Kashmir",
    "Ladakh", "Lakshadweep", "Puducherry",
]

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
    "data_source",
]


def get_api_key() -> str:
    api_key = os.getenv("MANDI_API_KEY")
    if not api_key:
        sys.exit(
            "ERROR: MANDI_API_KEY not found. Add it to a .env file:\n"
            "  MANDI_API_KEY=your_key_here"
        )
    return api_key


def fetch_page(api_key: str, offset: int, limit: int, state: str = None,
               max_retries: int = 8) -> dict:
    """Fetch a single page of records from the API, with retry/backoff."""
    params = {
        "api-key": api_key,
        "format": "json",
        "offset": offset,
        "limit": limit,
    }
    if state:
        params["filters[state.keyword]"] = state
    headers = {
        "Accept": "application/json",
        # The API silently stalls requests using Python's default
        # User-Agent header; spoofing curl's UA avoids that.
        "User-Agent": "curl/8.1.2",
    }

    for attempt in range(1, max_retries + 1):
        try:
            resp = requests.get(BASE_URL, params=params, headers=headers, timeout=60)
            if resp.status_code == 429:
                retry_after = resp.headers.get("Retry-After")
                wait = int(retry_after) if retry_after else min(10 * attempt, 60)
                print(f"    [warn] rate limited (429); waiting {wait}s "
                      f"(attempt {attempt}/{max_retries})")
                time.sleep(wait)
                continue
            resp.raise_for_status()
            data = resp.json()
            if "error" in data:
                sys.exit(f"ERROR from API: {data['error']}")
            return data
        except (requests.RequestException, ValueError) as exc:
            wait = 2 ** attempt  # 2s, 4s, 8s, 16s, 32s
            print(f"    [warn] request failed ({exc}); retrying in {wait}s "
                  f"(attempt {attempt}/{max_retries})")
            time.sleep(wait)

    print(f"    [error] giving up on state={state} offset={offset} "
          f"after {max_retries} attempts")
    return None


def determine_page_size(total: int, target_calls: int = 15,
                         min_size: int = 50, max_size: int = 300) -> int:
    """
    Picks a page size so a single state's pull takes roughly `target_calls`
    requests, regardless of how big that state's dataset is today.
    """
    if total <= min_size:
        return total or min_size
    ideal = -(-total // target_calls)  # ceil division
    return max(min_size, min(ideal, max_size))


def fetch_state_records(api_key: str, state: str) -> tuple:
    """
    Paginate through all records for a single state. Each state's result
    set individually stays well under the API's ~10,000 record window,
    which is the whole point of splitting the pull this way.

    Returns (records, complete) where complete is False if the pull had
    to give up early due to persistent failures.
    """
    records_for_state = []

    probe = fetch_page(api_key, offset=0, limit=1, state=state)
    if probe is None:
        print(f"  [error] skipping {state} entirely -- could not even probe it")
        return records_for_state, False
    total = int(probe.get("total", 0))

    if total == 0:
        return records_for_state, True

    page_size = determine_page_size(total)
    print(f"  {state}: {total} records -> page size {page_size}")

    offset = 0
    complete = True
    while offset < total:
        page = fetch_page(api_key, offset=offset, limit=page_size, state=state)
        if page is None:
            print(f"    [warn] stopping {state} early at offset={offset} "
                  f"({len(records_for_state)}/{total} collected) -- persistent failure")
            complete = False
            break
        records = page.get("records", [])
        if not records:
            break
        records_for_state.extend(records)
        offset += page_size
        time.sleep(1.0)  # pacing delay between page requests

    if total >= 9000:
        print(f"    [warn] {state} is close to the 10,000-record API window "
              f"({total}) -- consider splitting further by district if this "
              f"grows.")

    return records_for_state, complete


def fetch_all_records(api_key: str, max_state_retries: int = 3) -> list:
    """
    Pulls today's full dataset by looping over every state/UT and
    paginating each one separately, avoiding the API's ~10,000-record
    result window that a single flat query can silently hit.

    If any states fail (persistent errors after all page-level retries),
    automatically retries just those states, up to max_state_retries
    rounds, with a cooldown before each retry round -- no separate script
    or manual rerun needed.
    """
    records_by_state = {}
    states_to_try = list(STATES)
    round_num = 0

    while states_to_try and round_num <= max_state_retries:
        if round_num > 0:
            wait = 15 * round_num
            print(f"\nRetry round {round_num}: {len(states_to_try)} state(s) "
                  f"still incomplete ({', '.join(states_to_try)}). "
                  f"Waiting {wait}s before retrying...")
            time.sleep(wait)

        still_incomplete = []
        for state in states_to_try:
            state_records, complete = fetch_state_records(api_key, state)
            if state_records:
                # keep the most complete version we've gotten for this state
                existing = records_by_state.get(state, [])
                if len(state_records) >= len(existing):
                    records_by_state[state] = state_records
            if not complete:
                still_incomplete.append(state)
            time.sleep(1.0)  # cooldown between states, on top of per-page pacing

        states_to_try = still_incomplete
        round_num += 1

    all_records = [r for recs in records_by_state.values() for r in recs]

    print(f"\nTotal records fetched across all states: {len(all_records)}")
    if states_to_try:
        print(f"[warn] these states never fully succeeded after "
              f"{max_state_retries} retry rounds, data may be incomplete for: "
              f"{', '.join(states_to_try)}")
    return all_records


def main():
    parser = argparse.ArgumentParser(description="Extract Mandi daily price data.")
    parser.add_argument("--out-dir", type=str, default="./data",
                         help="Local directory to save the CSV into.")
    args = parser.parse_args()

    api_key = get_api_key()

    print("Fetching Mandi price data (per state, to stay under the API's "
          "10,000-record window per query)...")
    records = fetch_all_records(api_key)

    if not records:
        print("No records returned. Exiting without writing a file.")
        sys.exit(0)

    df = pd.DataFrame(records)
    df = df.drop_duplicates()

    # Tag every record from the live API as such, so it's distinguishable
    # from historical backfill data (e.g. from CEDA) once merged in Snowflake
    df["data_source"] = "live_api"

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