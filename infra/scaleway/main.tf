# =============================================================================
# ASH Backend Infrastructure - Scaleway (Blue-Green Deployment)
# =============================================================================
#
# Blue-Green deployment strategy:
# 1. Both slots always exist (no destruction during switch)
# 2. Active slot: min_scale=1+ (running instances)
# 3. Inactive slot: min_scale=0 (exists but no instances)
# 4. Deploy: create new slot -> health check -> switch DNS -> scale down old
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

  # Blue-green slot configuration - determines scaling, not existence
  is_blue_active  = var.active_slot == "blue"
  is_green_active = var.active_slot == "green"

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
# Both containers always exist. Active slot has min_scale=1+, inactive has min_scale=0.
# This ensures we never destroy the old container before the new one is healthy.

# Blue slot - always exists, scaling controlled by active_slot
resource "scaleway_container" "blue" {
  name           = "relay-${var.environment}-blue"
  namespace_id   = data.scaleway_container_namespace.main.id
  registry_image = "${data.scaleway_registry_namespace.main.endpoint}/ash-backend:${var.image_tag}"
  port           = 8080
  cpu_limit      = var.container_cpu_limit
  memory_limit   = var.container_memory_limit
  min_scale      = local.is_blue_active ? var.container_min_scale : 0
  max_scale      = var.container_max_scale  # Must be >= 1
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

  # Ensure new container is created before old one is modified
  lifecycle {
    create_before_destroy = true
  }
}

# Green slot - always exists, scaling controlled by active_slot
resource "scaleway_container" "green" {
  name           = "relay-${var.environment}-green"
  namespace_id   = data.scaleway_container_namespace.main.id
  registry_image = "${data.scaleway_registry_namespace.main.endpoint}/ash-backend:${var.image_tag}"
  port           = 8080
  cpu_limit      = var.container_cpu_limit
  memory_limit   = var.container_memory_limit
  min_scale      = local.is_green_active ? var.container_min_scale : 0
  max_scale      = var.container_max_scale  # Must be >= 1
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

  # Ensure new container is created before old one is modified
  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Active Container Reference
# =============================================================================

locals {
  # Get the active container's domain name and ID
  active_container_domain = local.is_blue_active ? scaleway_container.blue.domain_name : scaleway_container.green.domain_name
  active_container_id     = local.is_blue_active ? scaleway_container.blue.id : scaleway_container.green.id
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
