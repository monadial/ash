# =============================================================================
# ASH Backend Infrastructure - Scaleway (Blue-Green Deployment)
# =============================================================================
#
# Blue-Green deployment strategy:
# 1. Deploy new version to inactive slot
# 2. Health check passes
# 3. Switch DNS to new slot
# 4. Remove old container (min_scale=0 when inactive)
#
# Usage:
#   # Deploy to blue slot
#   terraform apply -var="environment=beta" -var="image_tag=sha-xxx" -var="active_slot=blue"
#
#   # Next deploy switches to green
#   terraform apply -var="environment=beta" -var="image_tag=sha-yyy" -var="active_slot=green"
#
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Environment-specific settings
  is_prod = var.environment == "prod"

  # Blue-green slot configuration
  slots = {
    blue  = var.active_slot == "blue"
    green = var.active_slot == "green"
  }

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
# Blue-Green Containers
# =============================================================================

# Blue slot - only created when active
resource "scaleway_container" "blue" {
  count          = local.slots.blue ? 1 : 0
  name           = "relay-${var.environment}-blue"
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
    SLOT        = "blue"
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

# Green slot - only created when active
resource "scaleway_container" "green" {
  count          = local.slots.green ? 1 : 0
  name           = "relay-${var.environment}-green"
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
    SLOT        = "green"
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
# Active Container Reference
# =============================================================================

locals {
  # Get the active container's domain name
  active_container_domain = var.active_slot == "blue" ? (
    length(scaleway_container.blue) > 0 ? scaleway_container.blue[0].domain_name : ""
  ) : (
    length(scaleway_container.green) > 0 ? scaleway_container.green[0].domain_name : ""
  )

  active_container_id = var.active_slot == "blue" ? (
    length(scaleway_container.blue) > 0 ? scaleway_container.blue[0].id : ""
  ) : (
    length(scaleway_container.green) > 0 ? scaleway_container.green[0].id : ""
  )
}

# =============================================================================
# DNS Configuration (Cloudflare) - Points to active slot
# =============================================================================

resource "cloudflare_record" "relay" {
  count   = local.create_dns ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = local.dns_name
  content = local.active_container_domain
  type    = "CNAME"
  proxied = false
  ttl     = 60  # Low TTL for faster failover
  comment = "ASH relay ${var.environment} (${var.active_slot}) - managed by Terraform"
}

# Link custom domain to active container
resource "scaleway_container_domain" "relay" {
  count        = local.create_dns ? 1 : 0
  container_id = local.active_container_id
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
