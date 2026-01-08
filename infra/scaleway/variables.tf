# =============================================================================
# Provider Configuration
# =============================================================================

variable "region" {
  description = "Scaleway region"
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = "Scaleway zone"
  type        = string
  default     = "fr-par-1"
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
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

# =============================================================================
# Container Configuration
# =============================================================================

variable "container_min_scale" {
  description = "Minimum number of container instances"
  type        = number
  default     = 0
}

variable "container_max_scale" {
  description = "Maximum number of container instances"
  type        = number
  default     = 5
}

variable "container_cpu_limit" {
  description = "CPU limit in millicores (1000 = 1 vCPU)"
  type        = number
  default     = 1000
}

variable "container_memory_limit" {
  description = "Memory limit in MB"
  type        = number
  default     = 512
}

# =============================================================================
# Domain Configuration
# =============================================================================

variable "domain" {
  description = "Custom domain for the relay (e.g., relay.ashprotocol.app)"
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
