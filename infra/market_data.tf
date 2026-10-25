# =============================================================================
# MARKET DATA
# The raw tables the Kaggle loader fills and the stress-scenario table you add
# rows to. OpenTofu owns these tables rather than Dataform so that a reload or
# an INSERT never needs a pipeline run.
# =============================================================================

resource "google_bigquery_table" "sp500_daily_prices" {
  dataset_id          = google_bigquery_dataset.stages["raw"].dataset_id
  table_id            = "sp500_daily_prices"
  description         = "RAW: daily split- and dividend-adjusted OHLCV for current S&P 500 members. Source: kaggle.com/datasets/${var.kaggle_dataset} (CC0)."
  deletion_protection = false

  # Column order must match the CSV header: date,open,high,low,close,volume,symbol
  schema = jsonencode([
    { name = "date", type = "DATE", description = "Trading date" },
    { name = "open", type = "FLOAT64", description = "Adjusted opening price" },
    { name = "high", type = "FLOAT64", description = "Adjusted daily high" },
    { name = "low", type = "FLOAT64", description = "Adjusted daily low" },
    { name = "close", type = "FLOAT64", description = "Adjusted closing price" },
    { name = "volume", type = "FLOAT64", description = "Shares traded" },
    { name = "symbol", type = "STRING", description = "Stock ticker" },
  ])
}

resource "google_bigquery_table" "sp500_companies" {
  dataset_id          = google_bigquery_dataset.stages["raw"].dataset_id
  table_id            = "sp500_companies"
  description         = "RAW: one row per current S&P 500 member. Source: kaggle.com/datasets/${var.kaggle_dataset} (CC0)."
  deletion_protection = false

  # Column order must match the CSV header.
  schema = jsonencode([
    { name = "symbol", type = "STRING", description = "Stock ticker" },
    { name = "company", type = "STRING", description = "Company name" },
    { name = "sector", type = "STRING", description = "GICS sector" },
    { name = "sub_industry", type = "STRING", description = "GICS sub-industry" },
    { name = "headquarters", type = "STRING", description = "Headquarters city and state" },
    { name = "date_added", type = "STRING", description = "Date the company joined the index, as published" },
    { name = "founded", type = "STRING", description = "Year founded, as published" },
  ])
}

resource "google_bigquery_table" "stress_scenarios" {
  dataset_id          = google_bigquery_dataset.stages["raw"].dataset_id
  table_id            = "stress_scenarios"
  description         = "RAW: stress scenarios the Monte Carlo simulates. Insert a row, then CALL serving.simulate_scenario('<scenario_id>')."
  deletion_protection = false

  schema = jsonencode([
    { name = "scenario_id", type = "STRING", mode = "REQUIRED", description = "Short identifier, such as energy_down_15" },
    { name = "description", type = "STRING", description = "What the scenario shocks" },
    { name = "sector", type = "STRING", description = "GICS sector to shock, exactly as in raw.sp500_companies. NULL shocks every stock." },
    { name = "shock_pct", type = "FLOAT64", mode = "REQUIRED", description = "Price shock applied on top of every simulated path, as a fraction: -0.15 is a 15% fall. 0 for no shock." },
  ])
}

resource "terraform_data" "load_market_data" {
  triggers_replace = [var.kaggle_dataset]

  depends_on = [
    google_storage_bucket.landing,
    google_bigquery_table.sp500_daily_prices,
    google_bigquery_table.sp500_companies,
    google_bigquery_table.stress_scenarios,
  ]

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/load_market_data.sh"
    environment = {
      PROJECT        = var.project_id
      BUCKET         = google_storage_bucket.landing.name
      DATASET        = google_bigquery_dataset.stages["raw"].dataset_id
      KAGGLE_DATASET = var.kaggle_dataset
    }
  }
}
