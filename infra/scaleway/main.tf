# =============================================================================
# ASH Backend Infrastructure - Scaleway
# =============================================================================
#
# This configuration provisions:
# - Container Registry namespace for Docker images
# - Serverless Container for running the backend
# - Optional custom domain configuration
#
# Usage:
#   terraform init
#   terraform plan
#   terraform apply
#
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = [
    "project=${var.project_name}",
    "environment=${var.environment}",
    "managed-by=terraform",
  ]
}

# =============================================================================
# Container Registry
# =============================================================================

# Use existing registry namespace (already created)
# Registry: rg.nl-ams.scw.cloud/ash-backend
data "scaleway_registry_namespace" "main" {
  name   = "ash-backend"
  region = var.region
}

# =============================================================================
# Serverless Container Namespace
# =============================================================================

resource "scaleway_container_namespace" "main" {
  name        = "${local.name_prefix}-containers"
  description = "Serverless containers for ASH backend"
  region      = var.region

  # Environment variables shared by all containers in namespace
  environment_variables = {
    RUST_LOG = "ash_backend=info,tower_http=info"
  }

  # Secret environment variables (APNS configuration)
  secret_environment_variables = var.apns_team_id != "" ? {
    APNS_TEAM_ID = var.apns_team_id
  } : {}
}

# =============================================================================
# Serverless Container - Backend
# =============================================================================

resource "scaleway_container" "backend" {
  name           = "${local.name_prefix}-backend"
  namespace_id   = scaleway_container_namespace.main.id
  registry_image = "${data.scaleway_registry_namespace.main.endpoint}/ash-backend:${var.image_tag}"
  port           = 8080
  cpu_limit      = var.container_cpu_limit
  memory_limit   = var.container_memory_limit
  min_scale      = var.container_min_scale
  max_scale      = var.container_max_scale
  timeout        = 300
  privacy        = "public"
  protocol       = "http1"
  deploy         = true

  environment_variables = {
    BIND_ADDR = "0.0.0.0"
    PORT      = "8080"
  }

  # Health check
  http_option = "redirected"
}

# =============================================================================
# Custom Domain (Optional)
# =============================================================================

resource "scaleway_container_domain" "backend" {
  count        = var.domain != "" ? 1 : 0
  container_id = scaleway_container.backend.id
  hostname     = var.domain
}

# =============================================================================
# Object Storage for APNS Key (Optional)
# =============================================================================

resource "scaleway_object_bucket" "secrets" {
  count = var.apns_team_id != "" ? 1 : 0
  name  = "${local.name_prefix}-secrets"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    enabled = true

    expiration {
      days = 90
    }
  }

  tags = {
    project     = var.project_name
    environment = var.environment
  }
}
