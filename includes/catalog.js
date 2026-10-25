// Labels that link a table to its Knowledge Catalog insights scan.
//
// The BigQuery console only shows a scan's generated descriptions and sample
// questions on the Insights tab when the table carries these three labels.
// Scans created in the console add them. Scans created by OpenTofu do not:
// https://cloud.google.com/bigquery/docs/generate-table-insights
//
// Dataform recreates each table and view on every run, which drops any label
// set outside Dataform. Setting them here keeps them on every run.
//
// The scan ID must match the insights scan in infra/data_scans.tf:
// the table name with underscores replaced by hyphens, plus "-insights".
function insightsLabels(table) {
  return {
    "dataplex-data-documentation-published-scan": `${table.replace(/_/g, "-")}-insights`,
    "dataplex-data-documentation-published-project": dataform.projectConfig.defaultDatabase,
    "dataplex-data-documentation-published-location": dataform.projectConfig.defaultLocation.toLowerCase(),
  };
}

module.exports = { insightsLabels };
