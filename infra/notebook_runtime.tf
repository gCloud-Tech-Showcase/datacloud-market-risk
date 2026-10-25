# =============================================================================
# NOTEBOOK RUNTIME
# BigQuery Studio notebooks run on a Colab Enterprise runtime, which needs a VPC
# network. New projects in many organizations have no default network, and the
# common org policy constraints/compute.vmExternalIpAccess blocks public IPs.
# This creates a small network with Private Google Access, so the runtime
# reaches BigQuery and the other Google APIs without a public IP, and a runtime
# template that uses it.
# =============================================================================

resource "google_compute_network" "notebooks" {
  name                    = "notebooks"
  auto_create_subnetworks = false

  depends_on = [time_sleep.api_propagation]
}

resource "google_compute_subnetwork" "notebooks" {
  name                     = "notebooks-${var.region}"
  region                   = var.region
  network                  = google_compute_network.notebooks.id
  ip_cidr_range            = "10.10.0.0/24"
  private_ip_google_access = true
}

resource "google_colab_runtime_template" "notebooks" {
  name         = "market-risk-notebooks"
  display_name = "Market risk notebooks"
  description  = "Runtime for the demo notebooks: private network, no public IP."
  location     = var.region

  machine_spec {
    machine_type = "e2-standard-4"
  }

  network_spec {
    network                = google_compute_network.notebooks.id
    subnetwork             = google_compute_subnetwork.notebooks.id
    enable_internet_access = false
  }

  # Stop an idle runtime so a forgotten session does not keep running.
  idle_shutdown_config {
    idle_timeout = "3600s"
  }

  labels = {
    purpose = "data-domain"
    domain  = "market-risk"
  }

  depends_on = [time_sleep.api_propagation]
}
