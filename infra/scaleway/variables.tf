# =============================================================================
# Provider Configuration
# =============================================================================

variable "region" {
  description = "Scaleway region"
  type        = string
  default     = "nl-ams"
}

variable "zone" {
  description = "Scaleway zone"
  type        = string
  default     = "nl-ams-1"
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

# =============================================================================
# Project Configuration
# =============================================================================

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "ash"
}

variable "environment" {
  description = "Environment (beta, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["beta", "prod"], var.environment)
    error_message = "Environment must be 'beta' or 'prod'."
  }
}

# =============================================================================
# Container Configuration
# =============================================================================

variable "container_min_scale" {
  description = "Minimum number of container instances"
  type        = number
  default     = 1
}

variable "container_max_scale" {
  description = "Maximum number of container instances"
  type        = number
  default     = 1
}

variable "container_cpu_limit" {
  description = "CPU limit in millicores (1000 = 1 vCPU, 250 = 0.25 vCPU)"
  type        = number
  default     = 250
}

variable "container_memory_limit" {
  description = "Memory limit in MB"
  type        = number
  default     = 256
}

# =============================================================================
# Cloudflare Configuration (DNS)
# =============================================================================

variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS edit permissions"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for ashprotocol.app"
  type        = string
  default     = ""
}

# =============================================================================
# APNS Configuration (Optional)
# =============================================================================

variable "apns_team_id" {
  description = "Apple Team ID for push notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "apns_key_id" {
  description = "APNS Key ID"
  type        = string
  default     = ""
  sensitive   = true
}

variable "apns_bundle_id" {
  description = "iOS App Bundle ID"
  type        = string
  default     = ""
}

variable "apns_sandbox" {
  description = "Use APNS sandbox environment"
  type        = bool
  default     = false
}
