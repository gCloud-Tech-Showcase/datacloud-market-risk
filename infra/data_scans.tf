# =============================================================================
# DATA PROFILE, QUALITY AND INSIGHTS SCANS
# Three scans on every data product asset, each run once on apply. Results are
# published to Knowledge Catalog, so they show on the table's Data profile,
# Data quality and Insights tabs in BigQuery, and on the data product.
#
# These complement the Dataform assertions in definitions/assertions/. An
# assertion stops a bad pipeline run. A quality scan publishes a pass or fail
# record per rule, by dimension, that a consumer can check for themselves.
#
# The scans run on demand only. Add a schedule trigger to re-run them.
# =============================================================================

locals {
  as_of_date = local.workflow_vars.as_of_date
  positions  = "`${var.project_id}.raw.portfolio_positions`"

  # One list of rules per asset. Each rule has a kind:
  #   non_null, unique  column checks
  #   range, set        column value checks
  #   row               a SQL condition every row must meet
  #   table             a SQL condition on the whole table, usually an aggregate
  #   sql               a query that returns the failing rows. ${data()} is the asset.
  quality_rules = {
    sp500_daily_prices = [
      { name = "close-is-positive", dimension = "VALIDITY", kind = "row", sql = "close > 0" },
      { name = "volume-not-negative", dimension = "VALIDITY", kind = "row", sql = "volume >= 0" },
      { name = "symbol-present", dimension = "COMPLETENESS", kind = "non_null", column = "symbol" },
      { name = "date-present", dimension = "COMPLETENESS", kind = "non_null", column = "date" },
      { name = "prices-reach-as-of-date", dimension = "FRESHNESS", kind = "table", sql = "MAX(date) >= DATE '${local.as_of_date}'" },
    ]
    sp500_companies = [
      { name = "one-row-per-symbol", dimension = "UNIQUENESS", kind = "unique", column = "symbol" },
      { name = "sector-is-gics", dimension = "VALIDITY", kind = "set", column = "sector", values = [
        "Communication Services", "Consumer Discretionary", "Consumer Staples", "Energy", "Financials", "Health Care",
        "Industrials", "Information Technology", "Materials", "Real Estate", "Utilities",
      ] },
    ]
    daily_returns = [
      # A handful of real single-day moves exceed 50% in ten years of 500
      # stocks, so the rule passes when 99.99% of returns are in range.
      { name = "returns-are-plausible", dimension = "VALIDITY", kind = "range", column = "log_return", min = "-0.5", max = "0.5", threshold = 0.9999 },
      { name = "returns-end-on-as-of-date", dimension = "FRESHNESS", kind = "table", sql = "MAX(date) = DATE '${local.as_of_date}'" },
      { name = "every-position-priced", dimension = "COMPLETENESS", kind = "sql", sql = "SELECT p.symbol FROM ${local.positions} AS p LEFT JOIN (SELECT symbol FROM $${data()} WHERE date = DATE '${local.as_of_date}') AS r USING (symbol) WHERE r.symbol IS NULL" },
    ]
    portfolio_positions = [
      { name = "one-row-per-symbol", dimension = "UNIQUENESS", kind = "unique", column = "symbol" },
      { name = "notional-is-positive", dimension = "VALIDITY", kind = "row", sql = "notional_usd > 0" },
      { name = "desk-is-known", dimension = "VALIDITY", kind = "set", column = "desk", values = ["Growth Equities", "Value Equities", "Defensive Equities"] },
      { name = "total-is-100m", dimension = "ACCURACY", kind = "table", sql = "ABS(SUM(notional_usd) - 100000000) < 1" },
    ]
    portfolio_var_summary = [
      { name = "var-99-at-least-var-95", dimension = "CONSISTENCY", kind = "row", sql = "var_99_usd >= var_95_usd" },
      { name = "es-at-least-var", dimension = "CONSISTENCY", kind = "row", sql = "es_95_usd >= var_95_usd AND es_99_usd >= var_99_usd" },
      { name = "baseline-has-both-methods", dimension = "COMPLETENESS", kind = "table", sql = "COUNT(DISTINCT IF(scenario_id = 'baseline', method, NULL)) = 2" },
    ]
    var_by_desk = [
      { name = "risk-not-negative", dimension = "VALIDITY", kind = "row", sql = "var_95_usd >= 0 AND var_99_usd >= 0 AND es_99_usd >= 0" },
      { name = "three-desks-per-scenario", dimension = "COMPLETENESS", kind = "sql", sql = "SELECT scenario_id FROM $${data()} GROUP BY scenario_id HAVING COUNT(DISTINCT desk) != 3" },
    ]
    var_contributions = [
      { name = "shares-add-up-to-100", dimension = "CONSISTENCY", kind = "sql", sql = "SELECT scenario_id FROM $${data()} GROUP BY scenario_id HAVING ABS(SUM(share_of_es_99_pct) - 100) > 0.5" },
      { name = "every-position-per-scenario", dimension = "COMPLETENESS", kind = "sql", sql = "SELECT scenario_id FROM $${data()} GROUP BY scenario_id HAVING COUNT(*) != (SELECT COUNT(*) FROM ${local.positions})" },
    ]
    timesfm_forward_params = [
      { name = "volatility-is-plausible", dimension = "VALIDITY", kind = "row", sql = "timesfm_vol_1d > 0 AND timesfm_vol_1d < 0.2" },
      { name = "every-position-forecast", dimension = "COMPLETENESS", kind = "sql", sql = "SELECT symbol FROM ${local.positions} WHERE symbol NOT IN (SELECT symbol FROM $${data()} WHERE timesfm_vol_1d IS NOT NULL)" },
    ]
  }

  # The Insights tab needs these labels on the table. Dataform sets them on the
  # tables it builds (includes/catalog.js). These are for the two raw tables
  # OpenTofu owns.
  insights_labels = {
    for table in ["sp500_daily_prices", "sp500_companies"] : table => {
      "dataplex-data-documentation-published-scan"     = "${replace(table, "_", "-")}-insights"
      "dataplex-data-documentation-published-project"  = var.project_id
      "dataplex-data-documentation-published-location" = var.region
    }
  }

  scans = merge([
    for table, asset in local.product_assets : {
      for kind in ["profile", "quality", "insights"] : "${replace(table, "_", "-")}-${kind}" => {
        table   = table
        dataset = asset.dataset
        kind    = kind
      }
    }
  ]...)
}

resource "google_project_service_identity" "dataplex" {
  provider = google-beta
  project  = var.project_id
  service  = "dataplex.googleapis.com"

  depends_on = [time_sleep.api_propagation]
}

resource "google_service_account" "data_scanner" {
  account_id   = "data-scanner"
  display_name = "Identity the profile, quality and insights scans run as"

  depends_on = [time_sleep.api_propagation]
}

resource "google_project_iam_member" "data_scanner_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = google_service_account.data_scanner.member
}

resource "google_bigquery_dataset_iam_member" "data_scanner_viewer" {
  for_each = toset(["raw", "processed", "serving"])

  dataset_id = google_bigquery_dataset.stages[each.key].dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = google_service_account.data_scanner.member
}

# Scans with a custom identity run as the Dataplex service agent impersonating
# that identity.
resource "google_service_account_iam_member" "dataplex_impersonates_scanner" {
  service_account_id = google_service_account.data_scanner.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = google_project_service_identity.dataplex.member
}

# Profile and quality scans can fail with an impersonation error for a minute
# or more after the grant.
resource "time_sleep" "scanner_iam_propagation" {
  create_duration = "3m"

  depends_on = [
    google_service_account_iam_member.dataplex_impersonates_scanner,
    google_project_iam_member.data_scanner_job_user,
    google_bigquery_dataset_iam_member.data_scanner_viewer,
  ]
}

resource "google_dataplex_datascan" "scan" {
  for_each = local.scans

  location     = var.region
  data_scan_id = each.key
  display_name = "${each.value.dataset}.${each.value.table} ${each.value.kind}"

  data {
    resource = "//bigquery.googleapis.com/projects/${var.project_id}/datasets/${each.value.dataset}/tables/${each.value.table}"
  }

  execution_spec {
    trigger {
      on_demand {}
    }
  }

  execution_identity {
    service_account {
      email = google_service_account.data_scanner.email
    }
  }

  dynamic "data_profile_spec" {
    for_each = each.value.kind == "profile" ? [1] : []
    content {
      catalog_publishing_enabled = true
    }
  }

  dynamic "data_quality_spec" {
    for_each = each.value.kind == "quality" ? [1] : []
    content {
      catalog_publishing_enabled = true

      dynamic "rules" {
        for_each = local.quality_rules[each.value.table]
        content {
          name        = rules.value.name
          dimension   = rules.value.dimension
          column      = try(rules.value.column, null)
          threshold   = try(rules.value.threshold, null)
          ignore_null = rules.value.kind == "range" ? true : null

          dynamic "non_null_expectation" {
            for_each = rules.value.kind == "non_null" ? [1] : []
            content {}
          }

          dynamic "uniqueness_expectation" {
            for_each = rules.value.kind == "unique" ? [1] : []
            content {}
          }

          dynamic "range_expectation" {
            for_each = rules.value.kind == "range" ? [1] : []
            content {
              min_value = rules.value.min
              max_value = rules.value.max
            }
          }

          dynamic "set_expectation" {
            for_each = rules.value.kind == "set" ? [1] : []
            content {
              values = rules.value.values
            }
          }

          dynamic "row_condition_expectation" {
            for_each = rules.value.kind == "row" ? [1] : []
            content {
              sql_expression = rules.value.sql
            }
          }

          dynamic "table_condition_expectation" {
            for_each = rules.value.kind == "table" ? [1] : []
            content {
              sql_expression = rules.value.sql
            }
          }

          dynamic "sql_assertion" {
            for_each = rules.value.kind == "sql" ? [1] : []
            content {
              sql_statement = rules.value.sql
            }
          }
        }
      }
    }
  }

  dynamic "data_documentation_spec" {
    for_each = each.value.kind == "insights" ? [1] : []
    content {
      catalog_publishing_enabled = true
    }
  }

  labels = { domain = "market-risk" }

  depends_on = [
    terraform_data.run_pipeline,
    time_sleep.scanner_iam_propagation,
  ]
}

# Starts the first run, so results are in the catalog when the apply finishes.
# Insights run after the profiles, because Gemini grounds its descriptions in
# profile results when they exist.
resource "terraform_data" "first_scan_run" {
  for_each = { for k, v in local.scans : k => v if v.kind != "insights" }

  triggers_replace = [google_dataplex_datascan.scan[each.key].id]

  provisioner "local-exec" {
    command = "gcloud dataplex datascans run ${each.key} --location=${var.region} --project=${var.project_id} --format=none"
  }
}

resource "time_sleep" "profile_results" {
  create_duration = "3m"

  depends_on = [terraform_data.first_scan_run]
}

resource "terraform_data" "first_insights_run" {
  for_each = { for k, v in local.scans : k => v if v.kind == "insights" }

  triggers_replace = [google_dataplex_datascan.scan[each.key].id]

  provisioner "local-exec" {
    command = "gcloud dataplex datascans run ${each.key} --location=${var.region} --project=${var.project_id} --format=none"
  }

  depends_on = [time_sleep.profile_results]
}
