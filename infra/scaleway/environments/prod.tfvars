# =============================================================================
# Production Environment Configuration
# =============================================================================

environment = "prod"

# Container resources (more resources for production)
container_cpu_limit    = 500   # 0.5 vCPU
container_memory_limit = 512   # 512 MB
container_min_scale    = 1     # Always keep at least 1 running
container_max_scale    = 1

# APNS (production)
apns_sandbox = false
