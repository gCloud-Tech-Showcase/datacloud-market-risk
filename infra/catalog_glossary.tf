# =============================================================================
# BUSINESS GLOSSARY
# The terms a risk reader needs, defined once in Knowledge Catalog and linked
# to the columns that hold them. Hover a linked column in BigQuery to see its
# definition. The definitions match the data agent's glossary in agent.tf.
# =============================================================================

locals {
  glossary_categories = {
    risk-measures = {
      display_name = "Risk measures"
      description  = "How the portfolio's potential loss is measured."
    }
    market-data = {
      display_name = "Market data"
      description  = "Prices and the statistics derived from them."
    }
    portfolio = {
      display_name = "Portfolio"
      description  = "How positions are organized and stressed."
    }
  }

  # Each term lists the columns it defines, as dataset.table.column.
  glossary_terms = {
    value-at-risk = {
      category     = "risk-measures"
      display_name = "Value at Risk (VaR)"
      description  = "The 1-day loss that portfolio P&L exceeds with only 1% probability (99% VaR) or 5% probability (95% VaR). Reported as a positive US dollar amount."
      columns = [
        "serving.portfolio_var_summary.var_95_usd",
        "serving.portfolio_var_summary.var_99_usd",
        "serving.var_by_desk.var_95_usd",
        "serving.var_by_desk.var_99_usd",
      ]
    }
    expected-shortfall = {
      category     = "risk-measures"
      display_name = "Expected Shortfall (ES)"
      description  = "The average 1-day loss on the outcomes beyond the VaR cut-off. Always at least as large as VaR at the same confidence level. Also called CVaR or conditional VaR."
      columns = [
        "serving.portfolio_var_summary.es_95_usd",
        "serving.portfolio_var_summary.es_99_usd",
        "serving.var_by_desk.es_99_usd",
        "serving.var_contributions.es_99_contribution_usd",
      ]
    }
    confidence-level = {
      category     = "risk-measures"
      display_name = "Confidence level"
      description  = "The probability level of a VaR or ES figure. A 99% 1-day VaR is the loss exceeded on about 1 day in 100. This repo reports 95% and 99%."
      columns      = []
    }
    holding-period = {
      category     = "risk-measures"
      display_name = "Holding period"
      description  = "The horizon a risk figure covers. Every VaR and ES figure in this repo is 1-day."
      columns      = []
    }
    filtered-historical-simulation = {
      category     = "risk-measures"
      display_name = "Filtered Historical Simulation (FHS)"
      description  = "The Monte Carlo method used here. Each path replays one day of standardized returns from the last 1,000 trading days, rescaled by each stock's TimesFM forward volatility, with a small amount of Gaussian smoothing."
      columns      = ["serving.portfolio_var_summary.method"]
    }
    daily-return = {
      category     = "market-data"
      display_name = "Daily return"
      description  = "The natural log of a day's adjusted close over the previous trading day's adjusted close."
      columns      = ["processed.daily_returns.log_return"]
    }
    volatility = {
      category     = "market-data"
      display_name = "Volatility"
      description  = "The standard deviation of daily log returns. TimesFM volatility is implied by the width of the forecast's 99% prediction interval. Historical volatility uses the last 252 trading days."
      columns = [
        "serving.timesfm_forward_params.timesfm_vol_1d",
        "serving.timesfm_forward_params.historical_vol_1d",
      ]
    }
    desk = {
      category     = "portfolio"
      display_name = "Desk"
      description  = "The trading desk that owns a position: Growth Equities, Value Equities or Defensive Equities."
      columns = [
        "raw.portfolio_positions.desk",
        "serving.var_by_desk.desk",
        "serving.var_contributions.desk",
      ]
    }
    book = {
      category     = "portfolio"
      display_name = "Book"
      description  = "A group of positions within a desk, such as US Tech or US Energy."
      columns      = ["raw.portfolio_positions.book"]
    }
    stress-scenario = {
      category     = "portfolio"
      display_name = "Stress scenario"
      description  = "A price shock applied to one sector, or to every stock, on top of every simulated path. 'baseline' has no shock. The result is VaR given the shock, not Basel stressed VaR."
      columns = [
        "serving.portfolio_var_summary.scenario_id",
        "serving.var_by_desk.scenario_id",
        "serving.var_contributions.scenario_id",
      ]
    }
  }

  glossary_links = merge([
    for term_id, term in local.glossary_terms : {
      for column in term.columns : "${term_id}:${column}" => {
        term_id = term_id
        dataset = split(".", column)[0]
        table   = split(".", column)[1]
        column  = split(".", column)[2]
      }
    }
  ]...)
}

resource "google_dataplex_glossary" "market_risk" {
  location     = var.region
  glossary_id  = "market-risk"
  display_name = "Market risk"
  description  = "Terms used in Pulsar Capital's market risk data products."

  depends_on = [time_sleep.api_propagation]
}

resource "google_dataplex_glossary_category" "category" {
  for_each = local.glossary_categories

  location     = var.region
  glossary_id  = google_dataplex_glossary.market_risk.glossary_id
  category_id  = each.key
  parent       = google_dataplex_glossary.market_risk.id
  display_name = each.value.display_name
  description  = each.value.description
}

resource "google_dataplex_glossary_term" "term" {
  for_each = local.glossary_terms

  location     = var.region
  glossary_id  = google_dataplex_glossary.market_risk.glossary_id
  term_id      = each.key
  parent       = google_dataplex_glossary_category.category[each.value.category].id
  display_name = each.value.display_name
  description  = each.value.description
}

# A definition link from a column to the term that defines it. The link lives
# in the @bigquery entry group, next to the table it annotates.
resource "google_dataplex_entry_link" "term_to_column" {
  for_each = local.glossary_links

  project         = data.google_project.current.number
  location        = var.region
  entry_group_id  = "@bigquery"
  entry_link_id   = substr(replace(lower("${each.value.term_id}-${each.value.table}-${each.value.column}"), "_", "-"), 0, 63)
  entry_link_type = "${local.dataplex_types}/entryLinkTypes/definition"

  entry_references {
    name = "${local.bigquery_entry_prefix}/bigquery.googleapis.com/projects/${var.project_id}/datasets/${each.value.dataset}/tables/${each.value.table}"
    path = "Schema.${each.value.column}"
    type = "SOURCE"
  }

  entry_references {
    name = "projects/${data.google_project.current.number}/locations/${var.region}/entryGroups/@dataplex/entries/projects/${data.google_project.current.number}/locations/${var.region}/glossaries/${google_dataplex_glossary.market_risk.glossary_id}/terms/${google_dataplex_glossary_term.term[each.value.term_id].term_id}"
    type = "TARGET"
  }

  depends_on = [terraform_data.run_pipeline]
}
