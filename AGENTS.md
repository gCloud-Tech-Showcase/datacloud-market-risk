# datacloud-market-risk

Standalone demo: 1-day Value at Risk on BigQuery for a fictional firm, Pulsar Capital. Kaggle S&P 500 prices (CC0) land in `raw`, TimesFM (`AI.FORECAST`) sets forward volatility, a stored procedure runs a 100K-path filtered historical simulation, and a Conversational Analytics data agent answers questions over the risk views. Knowledge Catalog publishes the tables as three data products with a glossary, aspects, lineage and one run of profile, quality and insights scans.

## Standing it up

```bash
./infra/scripts/setup.sh   # APIs + versioned state bucket + tofu init
cd infra && tofu apply     # zero required variables
```

**Tofu layout: flat.** Everything is in `infra/*.tf`, one apply, no `bootstrap/` stage.

Apply order: APIs → datasets and raw tables → `load_market_data.sh` (Kaggle → GCS → `bq load`, seeds `stress_scenarios`) → one Dataform pipeline run → data agent and Knowledge Catalog (data products, glossary, aspects, scans, then the first scan runs, insights 3 minutes after the rest). `run_pipeline` and `load_market_data` are `terraform_data` resources, so they run once; rerun the pipeline with `infra/scripts/run_pipeline.sh` (see `docs/quick.md`).

Dataform compiles from `main` on GitHub. Push SQL changes before running the pipeline.

Deploying elsewhere: change `project_id`'s default in `infra/variables.tf`, and `git_repo_url` if the SQL comes from a fork. Don't hardcode the project ID anywhere else.

## Words

| Term | Meaning here |
| --- | --- |
| VaR | 1-day Value at Risk, reported as a positive loss: the 1st (99%) or 5th (95%) percentile of portfolio P&L |
| ES | Expected Shortfall: average loss beyond the VaR cut-off |
| Path | One Monte Carlo draw: one replayed historical day plus per-stock noise |
| Scenario | A row of `raw.stress_scenarios`. `baseline` has no shock. |
| As-of date | `vars.as_of_date` in `workflow_settings.yaml`. Prices after it are ignored. |
| Reader | The person running the demo in their own project. Never "viewer" or "audience". |

## Data model

| Dataset | Object | What |
| --- | --- | --- |
| `raw` | `sp500_daily_prices`, `sp500_companies` | Kaggle files. OpenTofu-owned tables, Dataform declarations. |
| `raw` | `stress_scenarios` | OpenTofu-owned. Readers `INSERT` rows. |
| `raw` | `portfolio_positions` | Dataform table, 30 synthetic positions, $100M |
| `processed` | `daily_returns`, `standardized_returns` | Log returns; returns / trailing 63-day vol over the last 1,000 days |
| `serving` | `timesfm_forecast`, `timesfm_forward_params` | Raw `AI.FORECAST` output; derived 1-day vol |
| `serving` | `simulate_scenario` (procedure), `mc_simulated_pnl` | Monte Carlo. Both are Dataform `operations`. |
| `serving` | `portfolio_var_summary`, `var_by_desk`, `var_contributions`, `historical_pnl` | Risk views |
| `assertions` | `market_data_integrity`, `timesfm_forecast_complete`, `var_sanity` | Hard-fail checks |
| `assertions` | `risk_model_health` | Warning view |
| BigQuery Studio | Notebooks `01 Value At Risk`, `Run Pipeline` | Dataform repositories labelled `single-file-asset-type=notebook`, one per `notebooks/*.ipynb` |
| BigQuery Studio | Saved queries `00 Check` to `99 Reset` | Dataform repositories labelled `single-file-asset-type=sql`, one per `queries/*.sql` |

## Knowledge Catalog

| Object | What |
| --- | --- |
| Data products `market-data`, `trading-positions`, `market-risk-metrics` | 8 assets. `infra/data_products.tf`. Fictional owning teams in the descriptions. |
| Glossary `market-risk` | 3 categories, 10 terms, definition links to columns. `infra/catalog_glossary.tf`. |
| Aspect types `risk-metric-definition`, `model-description` | On the 3 VaR views and `timesfm_forward_params`. `infra/catalog_aspects.tf`. |
| Scans `<table>-profile`, `<table>-quality`, `<table>-insights` | One of each per asset, on demand. `infra/data_scans.tf`. |

Wording rule for anything regulatory: "inspired by" BCBS 239, plus the disclaimer in `docs/02-governed-risk-data.md`. Never "aligned to", "compliant with" or a principle-by-principle mapping. The model description has no validation or approval fields.

## Verifying

```sql
SELECT scenario_id, method, var_99_usd, es_99_usd, var_99_pct_notional
FROM `serving.portfolio_var_summary` ORDER BY method, scenario_id;
-- baseline monte_carlo: var_99_pct_notional between 1 and 3, es_99_usd > var_99_usd

SELECT * FROM `assertions.market_data_integrity`;      -- must be empty
SELECT * FROM `assertions.timesfm_forecast_complete`;  -- must be empty
SELECT * FROM `assertions.var_sanity`;                 -- must be empty
```

```bash
python3 scripts/verify_catalog.py   # every scan succeeded, every rule passed, products, terms, lineage
```

Correct, not just green: in `serving.var_by_desk`, desks with no stock in a scenario's sector have identical VaR in that scenario and in `baseline`.

## Gotchas

- **The simulation SQL lives only in `definitions/serving/simulate_scenario.sqlx`.** `mc_simulated_pnl` recreates the table and `CALL`s the procedure per scenario, so readers' `CALL`s and pipeline runs produce the same rows. Don't copy the simulation into another file.
- **Hashes, not `RAND()`.** The path-to-day mapping and the noise are `FARM_FINGERPRINT` hashes so that scenarios share draws. Switching to `RAND()` breaks the stress-minus-baseline comparison.
- **Without the noise term, 100K paths give only 1,000 distinct outcomes**, and tail metrics jump as tied blocks cross the cutoff.
- **`AI.FORECAST` is not exactly repeatable.** A pipeline rerun can move VaR by about 0.6%, and a change of region by a few percent. Docs say sample output differs slightly; keep it that way.
- **`AI.FORECAST` dates steps on calendar days.** Step 1 after a Friday is a Saturday. Read it as the next trading day.
- **Window functions run before `QUALIFY`.** Rank inside an already-filtered CTE (see `historical_pnl`).
- **`raw.stress_scenarios` sector values must match `raw.sp500_companies.sector` exactly** (`Information Technology`, `Health Care`). `NULL` shocks every stock.
- **Any edit to `infra/agent.tf` creates a new data agent with a new ID, then deletes the old one.** The provider's in-place update fails ("Last published context should not be set"), and a deleted agent keeps its ID for 30 days. Refer to the agent by its display name, **Pulsar Capital market risk**, never by ID.
- **Each SQL block in `docs/01-value-at-risk.md` has a saved query.** `queries/<NN>-<name>.sql` holds the same SQL as the block in step NN (`00` for the start check, `99` for Reset). Its first line is `-- <display name>`, and the guide names it next to the block. Change the guide, the query file and the notebook in the same commit.
- **Editing a notebook means editing `notebooks/*.ipynb` and running `tofu apply`.** The commit step reruns when the file hash changes and replaces the notebook in BigQuery Studio, including any edits made in the console.
- **The runtime template needs Secure Boot.** Orgs commonly enforce `constraints/compute.requireShieldedVm`, and a runtime from a template without it fails to start. The template has no fixed `name`, because a deleted template keeps its ID reserved.
- **Notebook runtimes have no public IP and no internet access.** Google APIs work through Private Google Access. `pip install` from PyPI does not, so notebooks use only preinstalled packages.
- **`run-pipeline.ipynb` sets `REGION` itself.** Keep it equal to `var.region`.
- **Adding a stage in `definitions/` means adding it to `infra/datasets.tf`.**
- **One region for everything.** `var.region` drives datasets, buckets, Dataform, notebooks and the catalog. `workflow_settings.yaml` (`defaultLocation`) and `run-pipeline.ipynb` repeat it. `run_pipeline.sh` passes it to Dataform, so the Tofu variable wins over the YAML. Never use the `US` multi-region: catalog scans need a single region.
- **Changing `var.region` on a live deployment fails with `409 Already Exists`.** The data agent's `create_before_destroy` spreads to everything it depends on, including the datasets, so Tofu creates the new datasets before deleting the old ones. Delete the datasets and landing bucket first, then apply with `-replace` on `load_market_data` and `run_pipeline`. A fresh project is not affected.
- **The Insights tab needs labels naming the scan.** Dataform sets them through `includes/catalog.js`, and `infra/market_data.tf` sets them on the two raw tables. A new data product asset needs both the label and a scan whose ID is the table name with hyphens plus `-insights`.
- **Catalog system types use the project number `655216118709`, not `dataplex-types`.** The API returns the number, so the name form makes every `tofu plan` replace the glossary links.
- **The data product owner needs an email.** ADC logins usually lack the email scope, so the owner falls back to the `dataform-runner` service account. Set `data_product_owner` in `infra/terraform.tfvars` to show a person.
- **Scans run once, at apply.** After a pipeline rerun the published results describe the previous run. Rerun them with `gcloud dataplex datascans run` (see `docs/02-governed-risk-data.md`).
- **Non-interactive shells don't load `.envrc`**, so pass `--project` to `bq` and `gcloud`.
- **Guide and quick reference show real output.** After changing SQL that feeds them, rerun the queries and update the samples.
- **The README points at `infra/variables.tf` line 13** for the `project_id` edit. If you move that line, update the line number, the `diff` block and the `perl` one-liner, and rerun the one-liner on a copy.

## Teardown

```bash
cd infra && tofu destroy
```

Removes everything Tofu created, including dataset contents, the landing bucket, the data agent and the Knowledge Catalog objects. Left behind: the project and `gs://<project>-tfstate`.

## More

`README.md` for setup, `docs/01-value-at-risk.md` for the guide, `docs/02-governed-risk-data.md` for the catalog, `docs/architecture.md` for the simulation method and observed product behaviour.
