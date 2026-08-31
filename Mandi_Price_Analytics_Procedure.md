# Mandi Price Analytics Dashboard — Project Procedure

**Stack:** data.gov.in Mandi API → Python → Azure ADLS Gen2 → Snowflake → Power BI

---

## 1. Project Setup

### 1.1 Get API Access
1. Go to [data.gov.in](https://data.gov.in) and create a free account.
2. Navigate to **My Account → API Keys** and generate your API key.
3. Search for the dataset: **"Variety-wise Daily Market Prices data of Various Commodities"** (resource under Ministry of Agriculture).
4. Note the **Resource ID** (a UUID) — you'll need it in every API call.
5. Test the API in a browser first:
   ```
   https://api.data.gov.in/resource/<resource_id>?api-key=<your_key>&format=json&limit=10
   ```
   Confirm you get a JSON response with fields like `state`, `district`, `market`, `commodity`, `variety`, `arrival_date`, `min_price`, `max_price`, `modal_price`.

### 1.2 Local Environment
1. Install Python 3.10+.
2. Create a project folder and virtual environment:
   ```bash
   mkdir mandi-price-analytics && cd mandi-price-analytics
   python -m venv venv
   venv\Scripts\activate     # Windows
   source venv/bin/activate  # Mac/Linux
   ```
3. Install required libraries:
   ```bash
   pip install requests pandas python-dotenv azure-storage-file-datalake
   ```
4. Create a `.env` file to store secrets (never hardcode keys):
   ```
   MANDI_API_KEY=your_key_here
   MANDI_RESOURCE_ID=your_resource_id_here
   AZURE_STORAGE_CONNECTION_STRING=your_connection_string_here
   ```
5. Create a `.gitignore` file and add `.env`, `venv/`, `__pycache__/` so secrets never get committed.

---

## 2. Data Ingestion (Python)

### 2.1 Write the Extraction Script
1. Create `extract_mandi_data.py`.
2. Load environment variables using `python-dotenv`.
3. Write a function `fetch_mandi_data(offset, limit, filters=None)` that calls the API with pagination parameters (the API typically caps `limit` at 1000 records per call) and optional date filters.
4. Loop through pages using `offset` until the API returns an empty result set, appending each page's records to a list.
5. Add error handling: retry on HTTP failures (use `requests` with a retry/backoff strategy), and log how many records were pulled.
6. Convert the collected records into a Pandas DataFrame.
7. Support two run modes via a script argument:
   - `--mode backfill --start-date --end-date` — loops through a historical date range in chunks (e.g., day by day or week by week) and pulls everything available.
   - `--mode daily` — pulls only the latest available date (usually yesterday, since mandi data has a reporting lag). This is the mode your daily scheduler will call.
8. Both modes write output using the **same partitioned path convention** (see 3.2), so Snowflake never needs separate logic for historical vs. daily data.

### 2.2 Local Validation
1. Save the DataFrame locally as a CSV first (`raw_mandi_YYYYMMDD.csv`) to sanity-check before touching the cloud.
2. Check row counts, null values, and confirm date formats are consistent.
3. Confirm price columns (`min_price`, `max_price`, `modal_price`) are numeric, not strings.

---

## 3. Azure Storage (Raw Landing Zone)

### 3.1 Create Azure Resources
1. Sign in to the [Azure Portal](https://portal.azure.com) (use free-tier/student credits if available).
2. Create a **Resource Group** (e.g., `rg-mandi-analytics`).
3. Create a **Storage Account** with **Hierarchical Namespace enabled** (this makes it ADLS Gen2, not plain Blob).
4. Inside the storage account, create a **Container** named `raw`.
5. Go to **Access Keys** (or **IAM**) and copy the connection string into your `.env` file.

### 3.2 Upload Script
1. Create `upload_to_adls.py`.
2. Use the `azure-storage-file-datalake` SDK to connect via the connection string.
3. Design a partitioned path structure for organization and easy incremental loading:
   ```
   raw/mandi/year=2026/month=08/day=31/mandi_prices.csv
   ```
4. Upload the CSV file created in Step 2.2 to this path.
5. Confirm the upload by listing files in the container via the Azure Portal or SDK.

### 3.3 One-Time Historical Backfill
1. Run `run_pipeline.py --mode backfill --start-date <earliest available> --end-date <yesterday>` once, in date-chunked batches, to populate history.
2. Verify record counts and spot-check a few dates against the API preview before moving on — backfills are the easiest place for silent gaps to creep in.
3. This only needs to run once; after this, only daily incremental runs are needed.

### 3.4 Daily Automation
Combine Steps 2 and 3 into a single script `run_pipeline.py` that extracts (`--mode daily`), validates, and uploads in one run. Two options to schedule it:

**Option A — Simple (fine for a portfolio project):**
- Windows Task Scheduler / cron job runs `run_pipeline.py --mode daily` once a day.
- Downside: only runs while your machine is on.

**Option B — Cloud-native (stronger resume story):**
- Deploy the script as an **Azure Function** with a **Timer Trigger** (e.g., daily at 6 AM).
- Removes the "my laptop must be on" dependency and gives you a concrete talking point in interviews: "I automated daily ingestion using a serverless timer-triggered function."

---

## 4. Snowflake (Transformation Layer)

### 4.1 Snowflake Setup
1. Sign up for a [Snowflake free trial](https://signup.snowflake.com/).
2. Create a **Database** (`MANDI_DB`), a **Warehouse** (`MANDI_WH`, X-Small size is enough), and a **Schema** (`RAW`, `STAGING`, `MART`).

### 4.2 Connect Snowflake to Azure
1. Create a **Storage Integration** object in Snowflake linking to your Azure storage account (this uses Azure AD app registration — Snowflake's docs walk through this exact handshake).
2. Create an **External Stage** in Snowflake pointing to your `raw` container path.
3. Grant the necessary permissions so Snowflake can read from ADLS.

### 4.3 Load Raw Data
1. Create a `RAW.MANDI_PRICES_RAW` table matching the CSV structure (all columns as `VARCHAR` initially — clean typing happens in staging).
2. Use `COPY INTO` for the initial historical load (this ingests everything from the backfill in one go).
3. For daily updates, set up **Snowpipe** with **auto-ingest** via Azure Event Grid notifications — new files landing in `raw/` after each daily run trigger an automatic load, no manual `COPY INTO` needed. This is a strong interview talking point.
4. If you'd rather skip Event Grid setup for simplicity, use a **Snowflake Task** scheduled to run `COPY INTO` once daily, a few hours after your ingestion job completes — simpler to set up, slightly less "real-time."

### 4.4 Staging & Cleaning
1. Create `STAGING.MANDI_PRICES_CLEAN` via a `CREATE TABLE AS SELECT` (CTAS) that:
   - Casts price fields to `NUMBER`
   - Casts `arrival_date` to `DATE`
   - Standardizes text fields (trim whitespace, uppercase state/commodity names)
   - Removes duplicate rows
   - Filters out nulls/invalid rows into a separate rejects table for data-quality tracking

### 4.5 Mart Layer (Star Schema)
1. Build dimension tables:
   - `DIM_COMMODITY` (commodity, variety)
   - `DIM_MARKET` (market, district, state)
   - `DIM_DATE` (calendar table generated via a `GENERATOR` function or recursive CTE)
2. Build the fact table:
   - `FACT_MANDI_PRICES` (foreign keys to each dimension + min_price, max_price, modal_price)
3. Create analytical views on top of the fact table:
   - `VW_PRICE_TRENDS` — average price by commodity/date
   - `VW_PRICE_VOLATILITY` — (max_price - min_price) spread per commodity/market
   - `VW_WOW_CHANGE` — week-over-week % price change using `LAG()` window functions
   - `VW_STATE_COMPARISON` — average modal price by state and commodity

---

## 5. Power BI (Presentation Layer)

### 5.1 Connect to Snowflake
1. Open Power BI Desktop → **Get Data → Snowflake**.
2. Enter your Snowflake account URL, warehouse, and database.
3. Choose **Import** mode for a small dataset, or **DirectQuery** if you want live data (more impressive but slower).
4. Load the mart views built in Step 4.5.

### 5.2 Data Model
1. In Power BI's Model view, confirm relationships between `FACT_MANDI_PRICES` and the dimension tables are auto-detected; fix any manually.
2. Mark `DIM_DATE` as a proper **Date Table** for time-intelligence functions.

### 5.3 Build DAX Measures
1. `Avg Modal Price = AVERAGE(FACT_MANDI_PRICES[modal_price])`
2. `Price Volatility = MAX(FACT_MANDI_PRICES[max_price]) - MIN(FACT_MANDI_PRICES[min_price])`
3. `WoW % Change` using `CALCULATE` + `DATEADD` for week-over-week comparison.
4. `Top Commodity by Price Gain` using `RANKX`.

### 5.4 Build Report Pages
1. **Overview page** — line chart of national average price trends by commodity over time; card visuals for headline stats (total markets tracked, total commodities, latest update date).
2. **State Comparison page** — Filled Map visual (choropleth) of India showing average modal price by state, with a commodity slicer.
3. **Volatility page** — bar chart ranking commodities/markets by price swing; useful narrative: "these commodities show the most supply-driven price instability."
4. **Drilldown/Explorer page** — a filterable table (state, market, commodity, date range slicers) for raw exploration.
5. Add a **Home/landing page** with a short description of the project and data source, since recruiters often click through decks quickly.

### 5.5 Daily Scheduled Refresh
1. Use **Import mode** (not DirectQuery) so the report performs well, and publish the report to the **Power BI Service**.
2. In the Service, go to the dataset's settings and configure **Scheduled Refresh** (e.g., daily at 8 AM, a couple hours after your Snowflake load completes).
3. Since Snowflake is cloud-native, Power BI's built-in Snowflake connector works without an on-premises gateway.
4. This closes the loop: ingestion (6 AM) → Snowflake load → Power BI refresh (8 AM) → dashboard is current every morning without you touching it.

### 5.6 Polish and Publish
1. Apply a consistent theme (colors, fonts) — Power BI has built-in themes, or import a custom JSON theme.
2. Add tooltips and clear axis titles.
3. Export a few screenshots/GIFs for your resume/portfolio/GitHub README.

---

## 6. Documentation & Portfolio Packaging

1. Create a `README.md` in your GitHub repo covering:
   - Problem statement (why mandi price transparency matters)
   - Architecture diagram (draw.io or even a simple image showing API → Azure → Snowflake → Power BI)
   - Setup instructions (how to reproduce)
   - **3–4 key insights** you found in the data (e.g., a commodity with unusual volatility, a state with consistently higher prices) — this is what turns a pipeline into an "analyst" story
2. Push the Python scripts (never the `.env` file) to GitHub.
3. Add screenshots of the Power BI dashboard directly in the README.
4. Write a 2–3 line project summary for your resume, e.g.:
   > "Built an end-to-end analytics pipeline ingesting daily agricultural commodity prices from the Government of India's open data API into Azure Data Lake and Snowflake, with a Power BI dashboard surfacing price trends and volatility across 500+ mandis."

---

## 7. Suggested Timeline

| Phase | Task | Est. Time |
|---|---|---|
| 1 | API access + Python ingestion script | 1–2 days |
| 2 | Azure setup + upload automation | 1 day |
| 3 | Snowflake staging + mart modeling | 2 days |
| 4 | Power BI dashboard build | 2 days |
| 5 | Documentation + GitHub polish | 1 day |

**Total: ~7–8 days** for a portfolio-ready project.
