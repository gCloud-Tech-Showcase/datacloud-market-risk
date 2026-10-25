# =============================================================================
# CONVERSATIONAL ANALYTICS DATA AGENT
# A BigQuery data agent over the risk views, so you can ask about VaR in plain
# English. It appears under BigQuery > Agents. The verified queries pin the
# definitions of VaR and Expected Shortfall so answers match the SQL.
# =============================================================================

locals {
  agent_tables = {
    serving = ["portfolio_var_summary", "var_by_desk", "var_contributions", "mc_simulated_pnl", "timesfm_forward_params", "historical_pnl"]
    raw     = ["portfolio_positions", "stress_scenarios"]
  }
  serving = "`${var.project_id}.serving`"
}

# The provider's in-place update sends back the read-only last_published_context,
# which the API rejects ("Last published context should not be set"). A deleted
# agent also keeps its ID for 30 days. So any edit to this file creates a new
# agent under a new ID, then deletes the old one. Find the agent by its display
# name, not its ID.
resource "google_gemini_data_analytics_data_agent" "market_risk" {
  location      = "global"
  data_agent_id = "pulsar_market_risk_${substr(filesha256("${path.module}/agent.tf"), 0, 8)}"
  display_name  = "Pulsar Capital market risk"
  description   = "Answers questions about 1-day Value at Risk and Expected Shortfall for Pulsar Capital's equity desks, including stress scenarios and TimesFM volatility."

  data_analytics_agent {
    published_context {
      system_instruction = <<-EOT
        You are a market risk analyst for Pulsar Capital, whose three equity desks
        (Growth, Value and Defensive Equities) hold about $100M of US large-cap stocks.
        All risk figures are 1-day. Report losses as positive US dollar amounts,
        rounded to the nearest thousand, and say which scenario and method a number
        comes from.

        Prefer the summary views: portfolio_var_summary for portfolio VaR and ES,
        var_by_desk for desk figures, var_contributions for which stocks drive the
        tail. Use mc_simulated_pnl only for distributions or cuts the views do not
        have. Portfolio P&L for one Monte Carlo path is SUM(sim_pnl_usd) grouped by
        scenario_id and path_id.

        Unless the user names a scenario, use scenario_id = 'baseline' and method =
        'monte_carlo'. Monte Carlo VaR uses TimesFM forward volatility; historical
        VaR replays the last 500 trading days. When they differ, look up the worst
        days in historical_pnl and compare timesfm_vol_annualized with
        historical_vol_annualized in timesfm_forward_params: a historical window that
        contains a selloff the forward view does not expect gives a higher
        historical VaR.
      EOT

      datasource_references {
        bq {
          dynamic "table_references" {
            for_each = flatten([for dataset, tables in local.agent_tables : [for t in tables : { dataset = dataset, table = t }]])
            content {
              project_id = var.project_id
              dataset_id = table_references.value.dataset
              table_id   = table_references.value.table
            }
          }
        }
      }

      glossary_terms {
        display_name = "VaR"
        description  = "Value at Risk: the 1-day loss that portfolio P&L exceeds with only 1% (99% VaR) or 5% (95% VaR) probability. Columns var_99_usd and var_95_usd."
        labels       = ["Value at Risk"]
      }
      glossary_terms {
        display_name = "Expected Shortfall"
        description  = "The average 1-day loss on the outcomes beyond the VaR cut-off. Always at least as large as VaR. Columns es_99_usd and es_95_usd."
        labels       = ["ES", "CVaR", "conditional VaR"]
      }
      glossary_terms {
        display_name = "stress scenario"
        description  = "A price shock applied to one sector, or to every stock, on top of every simulated path. Listed in raw.stress_scenarios; 'baseline' has no shock. The result is VaR given the shock, not Basel stressed VaR."
        labels       = ["stress test", "what-if", "shock"]
      }
      glossary_terms {
        display_name = "desk"
        description  = "Trading desk that owns a position: Growth Equities, Value Equities or Defensive Equities. Each desk has books such as US Tech or US Energy."
      }
      glossary_terms {
        display_name = "TimesFM volatility"
        description  = "1-day volatility implied by the TimesFM forecast's 99% prediction interval. Column timesfm_vol_1d in timesfm_forward_params."
        labels       = ["forward volatility", "forecast volatility"]
      }

      example_queries {
        natural_language_question = "What is our total portfolio 99% Value at Risk and Expected Shortfall across all desks?"
        sql_query                 = "SELECT var_99_usd, es_99_usd, var_99_pct_notional FROM ${local.serving}.portfolio_var_summary WHERE scenario_id = 'baseline' AND method = 'monte_carlo'"
      }
      example_queries {
        natural_language_question = "Compare the TimesFM forward-looking VaR against traditional historical VaR."
        sql_query                 = "SELECT method, var_95_usd, var_99_usd, es_99_usd FROM ${local.serving}.portfolio_var_summary WHERE scenario_id = 'baseline' ORDER BY method"
      }
      example_queries {
        natural_language_question = "Which days drive our historical VaR?"
        sql_query                 = "SELECT date, pnl_usd, worst_day_rank FROM ${local.serving}.historical_pnl ORDER BY worst_day_rank LIMIT 10"
      }
      example_queries {
        natural_language_question = "Which 5 stocks contribute the most tail risk?"
        sql_query                 = "SELECT symbol, sector, desk, es_99_contribution_usd, share_of_es_99_pct FROM ${local.serving}.var_contributions WHERE scenario_id = 'baseline' ORDER BY es_99_contribution_usd DESC LIMIT 5"
      }
      example_queries {
        natural_language_question = "How does the Energy shock change our 99% VaR by desk?"
        sql_query                 = "SELECT desk, MAX(IF(scenario_id = 'baseline', var_99_usd, NULL)) AS baseline_var_99_usd, MAX(IF(scenario_id = 'energy_down_15', var_99_usd, NULL)) AS stressed_var_99_usd FROM ${local.serving}.var_by_desk WHERE scenario_id IN ('baseline', 'energy_down_15') GROUP BY desk ORDER BY desk"
      }
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    time_sleep.api_propagation,
    terraform_data.run_pipeline,
  ]
}
