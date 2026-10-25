# Market Risk VaR on BigQuery Quick Reference

Copy-paste commands and queries, with sample output. Run the shell commands from the repository root, and the SQL in BigQuery Studio in your project.

> **Sample output only.** It comes from a run with an as-of date of 2026-10-23. TimesFM intervals vary slightly between runs, so check the shape of the output, not the exact values.

---

## 1. Rerun the pipeline

The first `tofu apply` runs the pipeline once. To run it again, for example after changing the as-of date in your fork, open the **Run Pipeline** notebook in BigQuery Studio and run all cells, or run the script:

```bash
cd infra
PROJECT=$(tofu output -raw project_id) REGION=us-central1 \
REPO=$(tofu output -raw dataform_repository_name) \
RUNNER_SA="dataform-runner@$(tofu output -raw project_id).iam.gserviceaccount.com" \
  bash scripts/run_pipeline.sh
```

```text
Attempt 1/8:
  compiled main: bc44a267-d08a-4813-9444-35dd8ca56f0e
  invocation started: 1792906324-fc1568fe-e165-4c51-90f2-4b7dc03d9f41
  state=RUNNING (1/80)
  ...
  pipeline SUCCEEDED
Done — domain is live.
```

---

## 2. Portfolio VaR and Expected Shortfall

```sql
SELECT scenario_id, method, ROUND(var_95_usd) AS var_95_usd, ROUND(var_99_usd) AS var_99_usd,
       ROUND(es_99_usd) AS es_99_usd, ROUND(var_99_pct_notional, 2) AS var_99_pct
FROM `serving.portfolio_var_summary`
ORDER BY method, scenario_id;
```

```text
+----------------+-------------+------------+------------+-----------+------------+
|  scenario_id   |   method    | var_95_usd | var_99_usd | es_99_usd | var_99_pct |
+----------------+-------------+------------+------------+-----------+------------+
| baseline       | historical  |  1465224.0 |  2732315.0 | 4424647.0 |       2.73 |
| baseline       | monte_carlo |  1391622.0 |  2330279.0 | 2977558.0 |       2.33 |
| energy_down_15 | monte_carlo |  3320900.0 |  4279703.0 | 4872998.0 |       4.28 |
+----------------+-------------+------------+------------+-----------+------------+
```

Correct, not just green: baseline Monte Carlo 99% VaR sits between 1% and 3% of notional, ES is above VaR, and the stress row is higher than the baseline.

---

## 3. VaR by desk

```sql
SELECT scenario_id, desk, ROUND(var_99_usd) AS var_99_usd, ROUND(es_99_usd) AS es_99_usd
FROM `serving.var_by_desk`
ORDER BY desk, scenario_id;
```

```text
+----------------+--------------------+------------+-----------+
|  scenario_id   |        desk        | var_99_usd | es_99_usd |
+----------------+--------------------+------------+-----------+
| baseline       | Defensive Equities |   653567.0 |  776571.0 |
| energy_down_15 | Defensive Equities |   653567.0 |  776571.0 |
| baseline       | Growth Equities    |  1512825.0 | 1927114.0 |
| energy_down_15 | Growth Equities    |  1512825.0 | 1927114.0 |
| baseline       | Value Equities     |   960446.0 | 1292367.0 |
| energy_down_15 | Value Equities     |  2855632.0 | 3170349.0 |
+----------------+--------------------+------------+-----------+
```

The sum of the desk VaRs is above the portfolio VaR. That gap is the diversification benefit.

---

## 4. Top tail contributors

```sql
SELECT symbol, sector, desk, ROUND(es_99_contribution_usd) AS es_99_contribution_usd,
       ROUND(share_of_es_99_pct, 1) AS share_pct
FROM `serving.var_contributions`
WHERE scenario_id = 'baseline'
ORDER BY es_99_contribution_usd DESC
LIMIT 5;
```

```text
+--------+------------------------+--------------------+------------------------+-----------+
| symbol |         sector         |        desk        | es_99_contribution_usd | share_pct |
+--------+------------------------+--------------------+------------------------+-----------+
| LULU   | Consumer Discretionary | Growth Equities    |               635778.0 |      21.4 |
| GOOGL  | Communication Services | Growth Equities    |               290793.0 |       9.8 |
| AAPL   | Information Technology | Growth Equities    |               151373.0 |       5.1 |
| LLY    | Health Care            | Defensive Equities |               143732.0 |       4.8 |
| JPM    | Financials             | Value Equities     |               135929.0 |       4.6 |
+--------+------------------------+--------------------+------------------------+-----------+
```

LULU is a $6M position in one of the more volatile stocks in the book, so it carries about a fifth of the tail on its own. That concentration is what this view is for.

---

## 5. Add and simulate a stress scenario

```sql
INSERT INTO `raw.stress_scenarios` (scenario_id, description, sector, shock_pct)
VALUES ('tech_down_10', 'Information Technology falls 10%', 'Information Technology', -0.10);

CALL `serving.simulate_scenario`('tech_down_10');
```

```text
Number of affected rows: 1
Number of affected rows: 0
Number of affected rows: 3000000
```

The `sector` value must match `raw.sp500_companies` exactly, for example `Information Technology` or `Health Care`. A `NULL` sector shocks every stock. To remove a scenario, delete it from `serving.mc_simulated_pnl` and `raw.stress_scenarios`.

---

## 6. Data quality

All three must return no rows. Any row fails the pipeline run:

```sql
SELECT * FROM `assertions.market_data_integrity`;
SELECT * FROM `assertions.timesfm_forecast_complete`;
SELECT * FROM `assertions.var_sanity`;
```

---

## 7. Monitoring

Rows here are a prompt to look, not a failure:

```sql
SELECT * FROM `assertions.risk_model_health`;
```

The view returned no rows in the sample run. A row names the check, the stock, the observed value and the expected range, for example a stock whose TimesFM volatility is less than half its trailing volatility.

---

## Navigation

[← Overview](README.md) | [Value at Risk](01-value-at-risk.md) | [Architecture](architecture.md)
