# =============================================================================
# DATA PRODUCTS
# Three data products, each owned by one (fictional) team. Market Risk Metrics
# consumes the other two:
#
#   Market Data ─────────┐
#                        ├──> Market Risk Metrics ──> Looker, the data agent, risk reporting
#   Trading Positions ───┘
#
# Everything lives in one project. The mesh comes from ownership, not from
# project boundaries.
# =============================================================================

locals {
  # Knowledge Catalog creates an entry for every BigQuery table and view in the
  # @bigquery entry group. Aspects and glossary links attach to those entries.
  bigquery_entry_prefix = "projects/${data.google_project.current.number}/locations/${var.region}/entryGroups/@bigquery/entries"

  # System entry types (bigquery-table, bigquery-view) and the glossary
  # definition link type live in this Google-owned project. The API returns
  # its number, so using the number keeps tofu plan clean.
  dataplex_types = "projects/655216118709/locations/global"

  # The pipeline's pinned settings, read from the Dataform config so they are
  # stated once.
  workflow_vars = yamldecode(file("${path.module}/../workflow_settings.yaml")).vars

  data_products = {
    market-data = {
      display_name = "Market Data"
      description  = "Owned by the Market Data team. Daily adjusted prices and GICS sectors for current S&P 500 members, and the daily log returns built from them. Prices are real (Kaggle, CC0), pinned to ${local.workflow_vars.as_of_date}. Used by Market Risk and quant research."
      assets = {
        sp500-daily-prices = { dataset = "raw", table = "sp500_daily_prices", entry_type = "bigquery-table" }
        sp500-companies    = { dataset = "raw", table = "sp500_companies", entry_type = "bigquery-table" }
        daily-returns      = { dataset = "processed", table = "daily_returns", entry_type = "bigquery-table" }
      }
    }
    trading-positions = {
      display_name = "Trading Positions"
      description  = "Owned by Middle Office. Pulsar Capital's equity positions: 30 long positions, about $100M, across three desks and five books. Synthetic. Used by Market Risk."
      assets = {
        portfolio-positions = { dataset = "raw", table = "portfolio_positions", entry_type = "bigquery-table" }
      }
    }
    market-risk-metrics = {
      display_name = "Market Risk Metrics"
      description  = "Owned by Market Risk. 1-day Value at Risk and Expected Shortfall for the portfolio and each desk, each position's share of the tail, and the TimesFM volatility behind the Monte Carlo. Built from Market Data and Trading Positions. Used by Looker dashboards, the data agent and risk reporting."
      assets = {
        portfolio-var-summary  = { dataset = "serving", table = "portfolio_var_summary", entry_type = "bigquery-view" }
        var-by-desk            = { dataset = "serving", table = "var_by_desk", entry_type = "bigquery-view" }
        var-contributions      = { dataset = "serving", table = "var_contributions", entry_type = "bigquery-view" }
        timesfm-forward-params = { dataset = "serving", table = "timesfm_forward_params", entry_type = "bigquery-view" }
      }
    }
  }

  # Every asset across the three products, keyed by table name.
  product_assets = merge([
    for product_id, product in local.data_products : {
      for asset_id, asset in product.assets : asset.table => merge(asset, {
        product_id = product_id
        asset_id   = asset_id
      })
    }
  ]...)
}

data "google_project" "current" {}

data "google_client_openid_userinfo" "deployer" {}

resource "google_dataplex_data_product" "product" {
  for_each = local.data_products

  location        = var.region
  data_product_id = each.key
  display_name    = each.value.display_name
  description     = each.value.description
  # The deployer's email is only known when the login has the email scope.
  # Without it, the pipeline's service account is listed as the owner.
  owner_emails = [coalesce(
    var.data_product_owner,
    data.google_client_openid_userinfo.deployer.email,
    google_service_account.dataform_runner.email,
  )]

  # Optional. When set, members of this Google group can read every asset in
  # the product, which is how a consumer team such as a Looker team gets access.
  dynamic "access_groups" {
    for_each = var.data_product_consumer_group == "" ? [] : [1]
    content {
      id           = "consumers"
      group_id     = "consumers"
      display_name = "Consumers"
      description  = "Teams that read this data product"

      principal {
        google_group = var.data_product_consumer_group
      }
    }
  }

  labels = { domain = "market-risk" }

  depends_on = [time_sleep.api_propagation]
}

resource "google_dataplex_data_product_data_asset" "asset" {
  for_each = local.product_assets

  location        = var.region
  data_product_id = google_dataplex_data_product.product[each.value.product_id].data_product_id
  data_asset_id   = each.value.asset_id
  resource        = "//bigquery.googleapis.com/projects/${var.project_id}/datasets/${each.value.dataset}/tables/${each.value.table}"

  dynamic "access_group_configs" {
    for_each = var.data_product_consumer_group == "" ? [] : [1]
    content {
      access_group = "consumers"
      iam_roles    = ["roles/bigquery.dataViewer"]
    }
  }

  depends_on = [terraform_data.run_pipeline]
}
