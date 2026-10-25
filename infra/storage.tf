# =============================================================================
# STORAGE
# The bucket the Kaggle files are staged in before they load into BigQuery.
# =============================================================================

resource "google_storage_bucket" "landing" {
  name                        = "${var.project_id}-landing"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  labels = {
    purpose = "data-domain"
    domain  = "market-risk"
  }

  depends_on = [time_sleep.api_propagation]
}
