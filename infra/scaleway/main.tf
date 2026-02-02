# =============================================================================
# ASH Backend Infrastructure - Scaleway
# =============================================================================
#
# Simple deployment: single container per environment.
#
# Usage:
#   terraform apply -var="environment=beta" -var="image_tag=sha-xxx"
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

data "scaleway_registry_namespace" "main" {
  name   = "ash-backend"
  region = var.region
}

# =============================================================================
# Serverless Container Namespace (shared between environments)
# =============================================================================

data "scaleway_container_namespace" "main" {
  name   = "ash-backend"
  region = var.region
}

# =============================================================================
# Serverless Container
# =============================================================================

resource "scaleway_container" "relay" {
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

  secret_environment_variables = var.apns_team_id != "" ? {
    APNS_TEAM_ID = var.apns_team_id
  } : {}

  http_option = "redirected"

  health_check {
    http {
      path = "/health"
    }
    failure_threshold = 3
    interval          = "30s"
  }
}

# =============================================================================
# DNS Configuration (Cloudflare)
# =============================================================================

resource "cloudflare_record" "relay" {
  count   = local.create_dns ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = local.dns_name
  content = scaleway_container.relay.domain_name
  type    = "CNAME"
  proxied = false
  ttl     = 300
  comment = "ASH relay ${var.environment} - managed by Terraform"
}

# Link custom domain to container
resource "scaleway_container_domain" "relay" {
  count        = local.create_dns ? 1 : 0
  container_id = scaleway_container.relay.id
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
