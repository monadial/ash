# =============================================================================
# Beta Environment Configuration
# =============================================================================

environment = "beta"

# Container resources (smaller for beta)
container_cpu_limit    = 250   # 0.25 vCPU
container_memory_limit = 256   # 256 MB
container_min_scale    = 0     # Scale to zero when idle
container_max_scale    = 2

# APNS (sandbox for beta)
apns_sandbox = true
