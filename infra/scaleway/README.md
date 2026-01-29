# ASH Backend - Scaleway Infrastructure

Terraform configuration for deploying the ASH backend to Scaleway Serverless Containers.

## Environments

| Environment | Trigger | Image Tag | Domain |
|-------------|---------|-----------|--------|
| **beta** | Push to `main` | `sha-xxxxxxx` | `eu.relay.beta.ashprotocol.app` |
| **prod** | Version tag (`v*`) | `v1.0.0` | `eu.relay.ashprotocol.app` |

## Container Specs

- **CPU**: 250 mvcpu (0.25 vCPU)
- **Memory**: 256 MB
- **Scaling**: 1-1 (always 1 instance)
- **Region**: nl-ams (Amsterdam)

## Prerequisites

1. **Terraform** >= 1.5.0
2. **Scaleway Account** with API keys
3. **S3 Bucket** for Terraform state: `ash-backend-tf-state`
4. **Container Registry**: `rg.nl-ams.scw.cloud/ash-backend`
5. **Container Namespace**: `ash-backend` (shared, contains `relay-prod` and `relay-beta`)

### Bootstrap (First Time)

```bash
# Create registry namespace and state bucket (one-time)
./bootstrap.sh
```

## Manual Deployment

### Deploy Beta

```bash
# Initialize with beta state
terraform init -backend-config="key=scaleway/beta/terraform.tfstate"

# Plan
terraform plan \
  -var="environment=beta" \
  -var="image_tag=sha-abc1234"

# Apply
terraform apply \
  -var="environment=beta" \
  -var="image_tag=sha-abc1234"
```

### Deploy Production

```bash
# Initialize with prod state (use -reconfigure if switching)
terraform init -backend-config="key=scaleway/prod/terraform.tfstate" -reconfigure

# Plan
terraform plan \
  -var="environment=prod" \
  -var="image_tag=v1.0.0"

# Apply
terraform apply \
  -var="environment=prod" \
  -var="image_tag=v1.0.0"
```

## GitHub Actions

Deployment is automated via `.github/workflows/deploy-backend.yml`:

| Trigger | Action |
|---------|--------|
| Push to `main` | Deploy to **beta** |
| Tag `v*` | Deploy to **prod** |
| Manual dispatch | Choose environment |

### Required Secrets (per GitHub Environment)

| Secret | Description |
|--------|-------------|
| `SCW_ACCESS_KEY` | Scaleway access key |
| `SCW_SECRET_KEY` | Scaleway secret key |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token (DNS edit permission) |

### Required Variables (per GitHub Environment)

| Variable | Description |
|----------|-------------|
| `SCW_DEFAULT_PROJECT_ID` | Scaleway project ID |
| `SCW_DEFAULT_ORGANIZATION_ID` | Scaleway organization ID |
| `CLOUDFLARE_ZONE_ID` | Cloudflare zone ID for ashprotocol.app |

### Creating Cloudflare API Token

1. Go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Create token with **Edit DNS** permission for `ashprotocol.app` zone
3. Copy the token to `CLOUDFLARE_API_TOKEN` secret

### Finding Cloudflare Zone ID

1. Go to Cloudflare dashboard → ashprotocol.app
2. Zone ID is shown on the right sidebar (Overview page)
3. Copy to `CLOUDFLARE_ZONE_ID` variable

### Creating a Production Release

```bash
# Tag a version
git tag v1.0.0
git push origin v1.0.0
```

This will:
1. Build multi-arch Docker image (amd64 + arm64)
2. Push to registry as `v1.0.0`
3. Deploy to production environment

## Outputs

```bash
# Get container URL
terraform output container_endpoint

# Get health check URL
terraform output health_check_url

# Get environment
terraform output environment
```

## DNS Configuration

DNS is automatically managed via Cloudflare. When Terraform runs:

1. Creates/updates CNAME record pointing to Scaleway container
2. Enables Cloudflare proxy (orange cloud) for SSL and DDoS protection
3. Links the domain to the Scaleway container

| Environment | Domain |
|-------------|--------|
| prod | `eu.relay.ashprotocol.app` |
| beta | `eu.relay.beta.ashprotocol.app` |

## Cost

Scaleway Serverless Containers pricing (nl-ams):
- 250 mvcpu + 256 MB = ~€0.000004/second when running
- With `min_scale=1`: Container always running (~€10/month)

## Troubleshooting

### Container not starting

Check logs in Scaleway Console or use:

```bash
scw container container logs <container-id>
```

### Health check failing

```bash
curl -v https://<container-endpoint>/health
```

### State locked

```bash
terraform force-unlock <lock-id>
```

### Switching between environments

```bash
# Re-initialize with different state
terraform init -backend-config="key=scaleway/beta/terraform.tfstate" -reconfigure
```
