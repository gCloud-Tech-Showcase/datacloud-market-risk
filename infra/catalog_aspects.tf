# =============================================================================
# CUSTOM ASPECTS
# Structured metadata on the risk views, so a reader can see how a number was
# produced without reading the SQL.
#
#   risk-metric-definition  on the three VaR views  = method, confidence, horizon
#   model-description       on timesfm_forward_params = the forecasting model
#
# The model description is descriptive only. It records what the model is and
# its known limits. It does not record a validation or approval status.
# =============================================================================

locals {
  risk_metric_definitions = {
    portfolio_var_summary = {
      metric            = "Portfolio Value at Risk and Expected Shortfall"
      method            = "Monte Carlo (filtered historical simulation, scaled by TimesFM volatility) and historical simulation for comparison"
      confidence_levels = "95%, 99%"
      horizon           = "1 trading day"
      lookback          = "Monte Carlo: last 1,000 trading days. Historical: last 500 trading days."
      simulation_paths  = local.workflow_vars.simulation_paths
      as_of_date        = local.workflow_vars.as_of_date
      positions         = "Today's positions held for one day. Long only."
    }
    var_by_desk = {
      metric            = "Standalone desk Value at Risk and Expected Shortfall"
      method            = "Monte Carlo (filtered historical simulation, scaled by TimesFM volatility). Each desk's P&L on the same paths as the portfolio."
      confidence_levels = "95%, 99%"
      horizon           = "1 trading day"
      lookback          = "Last 1,000 trading days"
      simulation_paths  = local.workflow_vars.simulation_paths
      as_of_date        = local.workflow_vars.as_of_date
      positions         = "Today's positions held for one day. Desk figures do not add up to the portfolio figure, because of diversification."
    }
    var_contributions = {
      metric            = "Position contribution to portfolio Expected Shortfall"
      method            = "Average P&L of each position on the Monte Carlo paths where the portfolio is in its worst 1%. Contributions add up to the portfolio's 99% Expected Shortfall."
      confidence_levels = "99%"
      horizon           = "1 trading day"
      lookback          = "Last 1,000 trading days"
      simulation_paths  = local.workflow_vars.simulation_paths
      as_of_date        = local.workflow_vars.as_of_date
      positions         = "Today's positions held for one day."
    }
  }

  model_description = {
    model        = "TimesFM 3.0 (Preview)"
    access       = "BigQuery AI.FORECAST. Zero-shot: no training or fine-tuning."
    purpose      = "Forecasts each stock's next-day close with a 99% prediction interval. The interval width sets the 1-day volatility that scales the Monte Carlo."
    inputs       = "Daily adjusted closes for the 30 portfolio stocks, last 4 years up to ${local.workflow_vars.as_of_date}"
    outputs      = "timesfm_vol_1d per stock, next to its trailing 252-day historical volatility for comparison"
    known_limits = "Returns a median and one prediction interval, not sample paths, so tails come from historical returns. Treats trading days as calendar days. Results can differ slightly between runs and regions."
    reference    = "https://cloud.google.com/bigquery/docs/reference/standard-sql/bigqueryml-syntax-ai-forecast"
  }
}

# A flat record of string fields, built from a list of field names.
locals {
  risk_metric_fields = ["metric", "method", "confidence_levels", "horizon", "lookback", "simulation_paths", "as_of_date", "positions"]
  model_fields       = ["model", "access", "purpose", "inputs", "outputs", "known_limits", "reference"]
}

resource "google_dataplex_aspect_type" "risk_metric_definition" {
  location       = var.region
  aspect_type_id = "risk-metric-definition"
  display_name   = "Risk metric definition"
  description    = "How a risk figure is calculated: method, confidence levels, horizon, lookback and simulation size."

  metadata_template = jsonencode({
    name = "risk_metric_definition"
    type = "record"
    recordFields = [
      for i, field in local.risk_metric_fields : { name = field, type = "string", index = i + 1 }
    ]
  })

  depends_on = [time_sleep.api_propagation]
}

resource "google_dataplex_aspect_type" "model_description" {
  location       = var.region
  aspect_type_id = "model-description"
  display_name   = "Model description"
  description    = "The model behind a table's values: what it is, how it is used and its known limits. Descriptive only."

  metadata_template = jsonencode({
    name = "model_description"
    type = "record"
    recordFields = [
      for i, field in local.model_fields : { name = field, type = "string", index = i + 1 }
    ]
  })

  depends_on = [time_sleep.api_propagation]
}

# BigQuery entries are created by Knowledge Catalog, not by Tofu. On an
# @bigquery entry the provider only patches the aspects listed here, leaves
# aspects written by scans alone, and on destroy drops the entry from state
# without deleting it.
resource "google_dataplex_entry" "risk_metric" {
  for_each = local.risk_metric_definitions

  project              = data.google_project.current.number
  location             = var.region
  entry_group_id       = "@bigquery"
  entry_id             = "bigquery.googleapis.com/projects/${var.project_id}/datasets/serving/tables/${each.key}"
  entry_type           = "${local.dataplex_types}/entryTypes/bigquery-view"
  fully_qualified_name = "bigquery:${var.project_id}.serving.${each.key}"
  parent_entry         = "${local.bigquery_entry_prefix}/bigquery.googleapis.com/projects/${var.project_id}/datasets/serving"

  aspects {
    aspect_key = "${data.google_project.current.number}.${var.region}.${google_dataplex_aspect_type.risk_metric_definition.aspect_type_id}"
    aspect {
      data = jsonencode(each.value)
    }
  }

  depends_on = [terraform_data.run_pipeline]
}

resource "google_dataplex_entry" "model" {
  project              = data.google_project.current.number
  location             = var.region
  entry_group_id       = "@bigquery"
  entry_id             = "bigquery.googleapis.com/projects/${var.project_id}/datasets/serving/tables/timesfm_forward_params"
  entry_type           = "${local.dataplex_types}/entryTypes/bigquery-view"
  fully_qualified_name = "bigquery:${var.project_id}.serving.timesfm_forward_params"
  parent_entry         = "${local.bigquery_entry_prefix}/bigquery.googleapis.com/projects/${var.project_id}/datasets/serving"

  aspects {
    aspect_key = "${data.google_project.current.number}.${var.region}.${google_dataplex_aspect_type.model_description.aspect_type_id}"
    aspect {
      data = jsonencode(local.model_description)
    }
  }

  depends_on = [terraform_data.run_pipeline]
}
