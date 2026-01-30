# =============================================================================
# ASH Backend Infrastructure - Scaleway
# =============================================================================
#
# This configuration provisions:
# - Container Registry namespace for Docker images
# - Serverless Containers for prod and beta environments
# - Optional custom domain configuration
#
# Environments:
# - prod: Deployed on version tags (v*)
# - beta: Deployed on push to main branch
#
# Usage:
#   terraform init
#   terraform plan -var="environment=beta" -var="image_tag=sha-xxx"
#   terraform apply -var="environment=prod" -var="image_tag=v1.0.0"
#
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Environment-specific settings
  is_prod = var.environment == "prod"

  # DNS configuration
  # prod: eu.relay.ashprotocol.app
  # beta: eu.relay.beta.ashprotocol.app
  dns_name    = local.is_prod ? "eu.relay" : "eu.relay.beta"
  full_domain = "${local.dns_name}.ashprotocol.app"
  create_dns  = var.cloudflare_api_token != "" && var.cloudflare_zone_id != ""

  common_tags = [
    "project=${var.project_name}",
    "environment=${var.environment}",
    "managed-by=terraform",
  ]
}

# =============================================================================
# Container Registry (pre-existing, shared between environments)
# =============================================================================

# Registry must exist before CI builds - create manually or via bootstrap
# Registry: rg.nl-ams.scw.cloud/ash-backend
data "scaleway_registry_namespace" "main" {
  name   = "ash-backend"
  region = var.region
}

# =============================================================================
# Serverless Container Namespace (shared between environments)
# =============================================================================

# Namespace is shared between prod and beta - lookup existing
# Create manually if needed: scw container namespace create name=ash-backend region=nl-ams
data "scaleway_container_namespace" "main" {
  name   = "ash-backend"
  region = var.region
}

# =============================================================================
# Serverless Container - Backend
# =============================================================================

resource "scaleway_container" "backend" {
  name           = "relay-${var.environment}"
  namespace_id   = data.scaleway_container_namespace.main.id
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
    RUST_LOG    = local.is_prod ? "ash_backend=info,tower_http=info" : "ash_backend=debug,tower_http=debug"
    ENVIRONMENT = var.environment
  }

  # Secret environment variables (APNS configuration)
  secret_environment_variables = var.apns_team_id != "" ? {
    APNS_TEAM_ID = var.apns_team_id
  } : {}

  # HTTP redirect option
  http_option = "redirected"

  # Health check probe
  health_check {
    http {
      path = "/health"
    }
    failure_threshold = 3
    interval          = "30s"
    timeout           = "10s"
  }
}

# =============================================================================
# DNS Configuration (Cloudflare)
# =============================================================================

# Cloudflare DNS record pointing to Scaleway container
resource "cloudflare_record" "relay" {
  count   = local.create_dns ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = local.dns_name
  content = scaleway_container.backend.domain_name
  type    = "CNAME"
  proxied = false  # Enable Cloudflare proxy for SSL/DDoS protection
  ttl     = 1     # Auto TTL when proxied
  comment = "ASH relay ${var.environment} - managed by Terraform"
}

# Link custom domain to Scaleway container
resource "scaleway_container_domain" "relay" {
  count        = local.create_dns ? 1 : 0
  container_id = scaleway_container.backend.id
  hostname     = local.full_domain
}

# =============================================================================
# Object Storage for APNS Key (Optional, prod only)
# =============================================================================

resource "scaleway_object_bucket" "secrets" {
  count = var.apns_team_id != "" && local.is_prod ? 1 : 0
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
