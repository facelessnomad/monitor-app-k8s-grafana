data "google_client_config" "default" {}

resource "google_service_account" "service_account" {
  account_id   = "service-account-id"
  display_name = "Monitoring Medium Service Accout"
  project      = var.project_id
}

resource "google_project_iam_member" "member-role" {
  depends_on = [google_service_account.service_account]
  for_each = toset([
    "roles/iam.serviceAccountUser",
    "roles/iam.serviceAccountAdmin",
    "roles/container.developer",
    "roles/container.clusterAdmin",
    "roles/compute.viewer"
  ])
  role    = each.key
  member  = "serviceAccount:${google_service_account.service_account.email}"
  project = var.project_id
}

resource "google_compute_network" "medium-monitoring-network" {
  name                    = "medium-monitoring-network"
  auto_create_subnetworks = false
  project                 = var.project_id
}

resource "google_compute_subnetwork" "medium-monitoring-subnetwork" {
  name          = "medium-monitoring-subnetwork"
  project       = var.project_id
  ip_cidr_range = "10.2.0.0/16"
  region        = "us-central1"
  network       = google_compute_network.medium-monitoring-network.id

  secondary_ip_range {
    range_name    = "us-central1-01-gke-01-pods"
    ip_cidr_range = "10.3.0.0/16"
  }

  secondary_ip_range {
    range_name    = "us-central1-01-gke-01-services"
    ip_cidr_range = "10.4.0.0/20"
  }
}

# Docs:
# https://registry.terraform.io/modules/terraform-google-modules/kubernetes-engine/google/latest/submodules/private-cluster
module "gke" {
  depends_on                 = [google_project_iam_member.member-role]
  deletion_protection        = false
  source                     = "terraform-google-modules/kubernetes-engine/google//modules/private-cluster"
  project_id                 = var.project_id
  name                       = var.cluster_name
  region                     = "us-central1"
  zones                      = ["us-central1-a"]
  network                    = google_compute_network.medium-monitoring-network.name
  subnetwork                 = google_compute_subnetwork.medium-monitoring-subnetwork.name
  ip_range_pods              = "us-central1-01-gke-01-pods"
  ip_range_services          = "us-central1-01-gke-01-services"
  http_load_balancing        = false
  network_policy             = false
  horizontal_pod_autoscaling = false
  filestore_csi_driver       = false
  enable_private_endpoint    = false
  enable_private_nodes       = false
  master_ipv4_cidr_block     = "10.0.0.0/28"
  dns_cache                  = false

  node_pools = [
    {
      name               = "default-node-pool"
      machine_type       = "e2-small"
      node_locations     = "us-central1-b,us-central1-c"
      min_count          = 3
      max_count          = 10
      local_ssd_count    = 0
      spot               = false
      disk_size_gb       = 30
      disk_type          = "pd-standard"
      image_type         = "COS_CONTAINERD"
      enable_gcfs        = false
      enable_gvnic       = false
      logging_variant    = "DEFAULT"
      auto_repair        = false
      auto_upgrade       = true
      service_account    = google_service_account.service_account.email
      preemptible        = true
      initial_node_count = 1
      accelerator_count  = 0
    },
  ]

  node_pools_oauth_scopes = {
    all = [
      # "https://www.googleapis.com/auth/logging.write",
      # "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/userinfo.email"
    ]
  }

  node_pools_labels = {
    all = {}

    default-node-pool = {
      default-node-pool = true
    }
  }

  node_pools_metadata = {
    all = {}

    default-node-pool = {
      node-pool-metadata-custom-value = "my-node-pool"
    }
  }

  node_pools_taints = {
    all = []

    default-node-pool = [
      {
        key    = "default-node-pool"
        value  = true
        effect = "PREFER_NO_SCHEDULE"
      },
    ]
  }

  node_pools_tags = {
    all = []

    default-node-pool = [
      "default-node-pool",
    ]
  }
}