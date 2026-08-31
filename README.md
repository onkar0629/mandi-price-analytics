# Mandi Price Analytics Pipeline

An end-to-end data pipeline ingesting daily agricultural commodity prices from the
Government of India's open data API (data.gov.in) into Azure Data Lake Storage Gen2,
transformed in Snowflake, and visualized in Power BI.

**Stack:** Python → Azure ADLS Gen2 → Snowflake → Power BI

## Data Source
- [Current Daily Price of Various Commodities from Various Markets (Mandi)](https://data.gov.in/) — Department of Agriculture and Farmers Welfare
- Resource ID: `9ef84268-d588-465a-a308-a864a43d0070`
- Fields: state, district, market, commodity, variety, grade, arrival_date, min_price, max_price, modal_price

## Pipeline Status
- [x] Python ingestion script (`extract_mandi_data.py`) — pulls and paginates through today's Mandi price records
- [x] Azure upload script (`upload_to_adls.py`) — pushes extracted CSV into ADLS Gen2, partitioned by date
- [ ] Snowflake staging + mart modeling
- [ ] Power BI dashboard
- [ ] Daily automation (scheduled ingestion + refresh)

## Setup

1. Clone the repo and install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
2. Copy `.env.example` to `.env` and fill in your own credentials:
   ```
   MANDI_API_KEY=your_data_gov_in_api_key
   AZURE_STORAGE_CONNECTION_STRING=your_azure_connection_string
   ```
3. Run the pipeline:
   ```bash
   python extract_mandi_data.py
   python upload_to_adls.py
   ```

## Architecture
```
data.gov.in Mandi API
    → extract_mandi_data.py (Python, paginated extraction)
    → local CSV (partitioned by date)
    → upload_to_adls.py
    → Azure Data Lake Storage Gen2 (raw/mandi/year=/month=/day=/)
    → Snowflake (staging → mart)
    → Power BI dashboard
```

## Notes
- The API silently times out on requests without a browser-like `User-Agent` header — the extraction script spoofs one to work around this.
- The "Current Daily Price" API only returns today's snapshot (no historical date filter); historical backfill is sourced separately.
