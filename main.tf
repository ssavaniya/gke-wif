# ------------------------------------------------------------------------------
# Provider Configuration
# ------------------------------------------------------------------------------
provider "google" {
  project = "proserv-task01"
  region  = "us-central1"
}

# ------------------------------------------------------------------------------
# Enable Required APIs
# ------------------------------------------------------------------------------
resource "google_project_service" "compute_api" {
  project            = "proserv-task01"
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "container_api" {
  project            = "proserv-task01"
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "resource_manager_api" {
  project            = "proserv-task01"
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

# ------------------------------------------------------------------------------
# VPC Network
# ------------------------------------------------------------------------------
resource "google_compute_network" "custom_vpc" {
  name                    = "my-tf-vpc"
  auto_create_subnetworks = false

  # Wait for Compute API to be enabled before creating the VPC
  depends_on = [google_project_service.compute_api]
}

# ------------------------------------------------------------------------------
# Subnetwork 
# ------------------------------------------------------------------------------
resource "google_compute_subnetwork" "custom_subnet" {
  name                     = "my-tf-subnet"
  ip_cidr_range            = "10.0.1.0/24"
  region                   = "us-central1"
  network                  = google_compute_network.custom_vpc.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "k8s-pod-range"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "k8s-service-range"
    ip_cidr_range = "10.2.0.0/20"
  }
}
# ------------------------------------------------------------------------------
# Cloud Router
# ------------------------------------------------------------------------------
resource "google_compute_router" "router" {
  name    = "my-cloud-router"
  region  = "us-central1"
  network = google_compute_network.custom_vpc.id
}

# ------------------------------------------------------------------------------
# Cloud NAT
# ------------------------------------------------------------------------------
resource "google_compute_router_nat" "nat" {
  name                               = "my-cloud-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  depends_on = [
    google_compute_router.router
  ]
}

# ------------------------------------------------------------------------------
# Firewall Rule 
# ------------------------------------------------------------------------------
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh-my-tf-vpc"
  network = google_compute_network.custom_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# ------------------------------------------------------------------------------
# GCE Instance
# ------------------------------------------------------------------------------
resource "google_compute_instance" "vm_instance" {
  name         = "my-tf-instance"
  machine_type = "e2-micro"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network    = google_compute_network.custom_vpc.id
    subnetwork = google_compute_subnetwork.custom_subnet.id
    
  }
}

# ------------------------------------------------------------------------------
# GKE Private Cluster
# ------------------------------------------------------------------------------
resource "google_container_cluster" "primary" {
  name     = "my-tf-cluster"
  location = "us-central1-a"

  network    = google_compute_network.custom_vpc.id
  subnetwork = google_compute_subnetwork.custom_subnet.id

  remove_default_node_pool = true
  initial_node_count       = 1

  ip_allocation_policy {
    cluster_secondary_range_name  = "k8s-pod-range"
    services_secondary_range_name = "k8s-service-range"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }
  depends_on = [
    google_project_service.container_api,
    google_project_service.compute_api
  ]
}

# ------------------------------------------------------------------------------
# GKE Node Pool
# ------------------------------------------------------------------------------
resource "google_container_node_pool" "primary_nodes" {
  name       = "my-node-pool"
  location   = "us-central1-a"
  cluster    = google_container_cluster.primary.name
  node_count = 1

  node_config {
    preemptible  = true
    machine_type = "e2-medium"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}
