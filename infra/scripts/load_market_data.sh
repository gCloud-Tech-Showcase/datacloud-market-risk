#!/usr/bin/env bash
# Download the Kaggle S&P 500 dataset, stage it in GCS and load it into the raw
# BigQuery tables that OpenTofu created. Called by `tofu apply`; safe to rerun.
#
# Required environment: PROJECT, BUCKET, DATASET, KAGGLE_DATASET.
set -euo pipefail

: "${PROJECT:?}" "${BUCKET:?}" "${DATASET:?}" "${KAGGLE_DATASET:?}"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# Kaggle serves public datasets without credentials: this endpoint redirects to
# a signed download URL.
for file in sp500_stocks.csv sp500_companies.csv; do
  echo "==> Downloading ${file} from kaggle.com/datasets/${KAGGLE_DATASET}"
  curl -fsSL --retry 3 -o "${work_dir}/${file}" \
    "https://www.kaggle.com/api/v1/datasets/download/${KAGGLE_DATASET}/${file}"
  gcloud storage cp --project="$PROJECT" "${work_dir}/${file}" "gs://${BUCKET}/kaggle/${file}"
done

echo "==> Loading ${DATASET}.sp500_daily_prices"
bq --project_id="$PROJECT" load --replace --source_format=CSV --skip_leading_rows=1 \
  "${DATASET}.sp500_daily_prices" "gs://${BUCKET}/kaggle/sp500_stocks.csv"

echo "==> Loading ${DATASET}.sp500_companies"
bq --project_id="$PROJECT" load --replace --source_format=CSV --skip_leading_rows=1 \
  --allow_quoted_newlines \
  "${DATASET}.sp500_companies" "gs://${BUCKET}/kaggle/sp500_companies.csv"

# MERGE, not INSERT, so a rerun keeps any scenarios you added yourself.
echo "==> Seeding ${DATASET}.stress_scenarios"
bq --project_id="$PROJECT" query --use_legacy_sql=false --quiet "
MERGE \`${PROJECT}.${DATASET}.stress_scenarios\` AS t
USING (
  SELECT 'baseline' AS scenario_id, 'No shock' AS description, CAST(NULL AS STRING) AS sector, 0.0 AS shock_pct
  UNION ALL
  SELECT 'energy_down_15', 'Energy sector falls 15%', 'Energy', -0.15
) AS s
ON t.scenario_id = s.scenario_id
WHEN NOT MATCHED THEN INSERT ROW"

echo "==> Market data loaded"
