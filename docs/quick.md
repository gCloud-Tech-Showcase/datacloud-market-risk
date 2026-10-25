# Market Risk VaR on BigQuery Quick Reference

Copy-paste commands and queries, with sample output. Run the shell commands from the repository root, and the SQL in BigQuery Studio in your project.

> **Sample output only.** It comes from a run with an as-of date of 2026-10-23. TimesFM intervals vary slightly between runs, so check the shape of the output, not the exact values.

---

## 1. Rerun the pipeline

The first `tofu apply` runs the pipeline once. To run it again, for example after changing the as-of date in your fork:

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
| baseline       | historical  |  1407881.0 |  2792426.0 | 4435897.0 |       2.79 |
| baseline       | monte_carlo |  1171371.0 |  1810869.0 | 2608236.0 |       1.81 |
| energy_down_15 | monte_carlo |  3102284.0 |  3706239.0 | 4497174.0 |       3.71 |
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
| baseline       | Defensive Equities |   613140.0 |  744931.0 |
| energy_down_15 | Defensive Equities |   613140.0 |  744931.0 |
| baseline       | Growth Equities    |  1034867.0 | 1284023.0 |
| energy_down_15 | Growth Equities    |  1034867.0 | 1284023.0 |
| baseline       | Value Equities     |   964040.0 | 1299671.0 |
| energy_down_15 | Value Equities     |  2856091.0 | 3178204.0 |
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
+--------+------------------------+-----------------+------------------------+-----------+
| symbol |         sector         |      desk       | es_99_contribution_usd | share_pct |
+--------+------------------------+-----------------+------------------------+-----------+
| AMZN   | Consumer Discretionary | Growth Equities |               242869.0 |       9.3 |
| JPM    | Financials             | Value Equities  |               200830.0 |       7.7 |
| MS     | Financials             | Value Equities  |               154516.0 |       5.9 |
| NVDA   | Information Technology | Growth Equities |               148192.0 |       5.7 |
| AAPL   | Information Technology | Growth Equities |               147032.0 |       5.6 |
+--------+------------------------+-----------------+------------------------+-----------+
```

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

```text
+------------------------------+--------+--------------------+----------------+
|          check_name          | symbol |       value        | expected_range |
+------------------------------+--------+--------------------+----------------+
| TimesFM vol / historical vol | MSFT   | 0.3619745774101493 | 0.5 to 1.5     |
+------------------------------+--------+--------------------+----------------+
```

---

## Navigation

[← Overview](README.md) | [Value at Risk](01-value-at-risk.md) | [Architecture](architecture.md)
