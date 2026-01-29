# =============================================================================
# Outputs
# =============================================================================

# Environment
output "environment" {
  description = "Deployment environment"
  value       = var.environment
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

# Container
output "container_endpoint" {
  description = "Serverless container endpoint URL"
  value       = scaleway_container.backend.domain_name
}

output "container_id" {
  description = "Serverless container ID"
  value       = scaleway_container.backend.id
}

# Custom Domain
output "custom_domain" {
  description = "Custom domain for the backend"
  value       = local.create_dns ? local.full_domain : null
}

output "relay_url" {
  description = "Full relay URL"
  value       = local.create_dns ? "https://${local.full_domain}" : "https://${scaleway_container.backend.domain_name}"
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
  value       = "https://${scaleway_container.backend.domain_name}/health"
}
