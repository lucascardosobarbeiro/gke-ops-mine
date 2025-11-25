terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "google" {
  project = "minecraft-server-iac" # <--- COLOCAR SEU ID
  region  = "us-central1"
}

# --- 1. GKE Cluster ---
resource "google_container_cluster" "primary" {
  name     = "minecraft-cluster"
  location = "us-central1-a"

  # Importante para conseguir destruir depois
  deletion_protection = false

  remove_default_node_pool = true
  initial_node_count       = 1
}

# --- 2. Node Pool (A Máquina Potente) ---
resource "google_container_node_pool" "primary_nodes" {
  name       = "minecraft-pool"
  cluster    = google_container_cluster.primary.id
  node_count = 1 # Para Minecraft, 1 nó parrudo é melhor que vários fracos

  node_config {
    preemptible  = true            # Spot VM (Mais barato, reseta a cada 24h)
    machine_type = "e2-standard-2" # 8GB RAM / 2 vCPUs
    disk_size_gb = 50              # Espaço em disco do sistema

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# --- 3. Instalação do Argo CD ---
data "google_client_config" "default" {}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "5.46.7"
  timeout          = 600

  depends_on = [google_container_node_pool.primary_nodes]
}
