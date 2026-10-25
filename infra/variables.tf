# =============================================================================
# VARIABLES
# Every variable has a working default, so a clone is `setup.sh` then `apply`
# with no tfvars file. `project_id`'s default below is the SINGLE SOURCE OF
# TRUTH for this domain repo: providers, resources, derived bucket names and
# scripts/setup.sh all read from it. Never restate a project ID or bucket name
# anywhere else — derive it.
# =============================================================================

variable "project_id" {
  description = "The GCP project ID (created out-of-band as a one-time prerequisite)"
  type        = string
  default     = "datacloud-market-risk"
}

variable "region" {
  description = "The one region for every resource: BigQuery datasets, buckets, Dataform, notebooks and the catalog. workflow_settings.yaml and notebooks/run-pipeline.ipynb repeat it, so change them too."
  type        = string
  default     = "us-central1"
}

# [visibility:public]
variable "git_repo_url" {
  description = "GitHub repository URL the managed Dataform repo pulls from. HTTPS because the link is anonymous and tokenless, which only reaches a public repo."
  type        = string
  default     = "https://github.com/gCloud-Tech-Showcase/datacloud-market-risk.git"
}




variable "kaggle_dataset" {
  description = "Kaggle dataset (owner/name) that infra/scripts/load_market_data.sh downloads. It must contain sp500_stocks.csv and sp500_companies.csv in the same columns."
  type        = string
  default     = "darkmatternet/s-and-p-500-stocks-25-years-of-data-updated-daily"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$", var.kaggle_dataset))
    error_message = "kaggle_dataset must be <owner>/<dataset>, as in the dataset's Kaggle URL."
  }
}

variable "run_pipeline_on_apply" {
  description = "Trigger a Dataform run (compile main + workflow invocation as the runner SA) as the final step of apply and block until it finishes, so a fresh apply leaves the domain fully built. Runs once on first apply; set false to skip."
  type        = bool
  default     = true
}

variable "enable_scheduled_runs" {
  description = "Create the Dataform release + workflow configs that compile and run the pipeline hourly. Off by default so a clone-and-apply is a one-shot build with no recurring cost on a forker's project; set true for a self-refreshing deployment."
  type        = bool
  default     = false
}


variable "data_product_owner" {
  description = "Email listed as the owner of the three data products. Empty means the account running tofu apply, or the pipeline service account if that email is not available."
  type        = string
  default     = ""
}

variable "data_product_consumer_group" {
  description = "Optional Google group (email) granted read access to every data product asset, as a consumer team would be. Empty means no access group."
  type        = string
  default     = ""
}
