# =============================================================================
# Outputs - Blue-Green Deployment
# =============================================================================

# Environment
output "environment" {
  description = "Deployment environment"
  value       = var.environment
}

output "active_slot" {
  description = "Currently active deployment slot"
  value       = var.active_slot
}

# Registry
output "registry_endpoint" {
  description = "Container registry endpoint"
  value       = data.scaleway_registry_namespace.main.endpoint
}

output "registry_namespace" {
  description = "Container registry namespace ID"
  value       = data.scaleway_registry_namespace.main.id
}

# Active Container
output "container_endpoint" {
  description = "Active container endpoint URL"
  value       = local.active_container_domain
}

output "container_id" {
  description = "Active container ID"
  value       = local.active_container_id
}

# Custom Domain
output "custom_domain" {
  description = "Custom domain for the backend"
  value       = local.create_dns ? local.full_domain : null
  sensitive   = true
}

output "relay_url" {
  description = "Full relay URL"
  value       = local.create_dns ? "https://${local.full_domain}" : "https://${local.active_container_domain}"
  sensitive   = true
}

# Docker Commands
output "docker_login_command" {
  description = "Command to login to the container registry"
  value       = "docker login ${data.scaleway_registry_namespace.main.endpoint} -u nologin --password-stdin <<< $SCW_SECRET_KEY"
}

output "docker_push_command" {
  description = "Command to push the backend image"
  value       = "docker push ${data.scaleway_registry_namespace.main.endpoint}/ash-backend:latest"
}

# Health Check
output "health_check_url" {
  description = "Health check endpoint"
  value       = "https://${local.active_container_domain}/health"
}

# Next Deployment Info
output "next_slot" {
  description = "Slot to use for next deployment"
  value       = var.active_slot == "blue" ? "green" : "blue"
}
