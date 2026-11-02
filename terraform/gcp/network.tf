resource "google_compute_network" "cluster" {
  name                    = var.cluster_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "cluster" {
  name                     = var.cluster_name
  region                   = var.region
  network                  = google_compute_network.cluster.id
  ip_cidr_range            = "10.81.0.0/24"
  private_ip_google_access = true
}

resource "google_compute_firewall" "internal" {
  name        = "${var.cluster_name}-internal"
  network     = google_compute_network.cluster.name
  source_tags = local.tags
  target_tags = local.tags
  allow { protocol = "all" }
}

resource "google_compute_firewall" "management" {
  name          = "${var.cluster_name}-management"
  network       = google_compute_network.cluster.name
  source_ranges = var.management_cidrs
  target_tags   = ["${var.cluster_name}-controlplane"]
  allow {
    protocol = "tcp"
    ports    = ["6443", "50000"]
  }
}

resource "google_compute_address" "controlplane" {
  name   = "${var.cluster_name}-api"
  region = var.region
}
