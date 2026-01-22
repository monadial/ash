# ASH Infrastructure - Scaleway

Terraform configuration for provisioning ASH backend infrastructure on Scaleway.

## Resources

- **Container Registry**: Private registry for Docker images
- **Serverless Container**: Auto-scaling container for the backend
- **Custom Domain**: Optional custom domain binding

## Prerequisites

1. [Terraform](https://www.terraform.io/downloads) >= 1.5.0
2. [Scaleway CLI](https://github.com/scaleway/scaleway-cli) (optional, for local testing)
3. Scaleway API credentials

## Setup

### 1. Configure Credentials

```bash
export SCW_ACCESS_KEY="your-access-key"
export SCW_SECRET_KEY="your-secret-key"
export SCW_DEFAULT_PROJECT_ID="your-project-id"
```

Get credentials from: https://console.scaleway.com/iam/api-keys

### 2. Create Variables File

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 3. Bootstrap State Bucket (First Time Only)

Before running Terraform for the first time, create the S3 bucket for storing state:

```bash
./bootstrap.sh
```

### 4. Initialize and Apply

```bash
terraform init
terraform plan
terraform apply
```

## Outputs

After applying, you'll get:

| Output | Description |
|--------|-------------|
| `registry_endpoint` | Docker registry URL |
| `container_endpoint` | Backend API URL |
| `health_check_url` | Health check endpoint |
| `docker_login_command` | Command to login to registry |

## Pushing Docker Images

```bash
# Build the image
cd backend
docker build -t ash-backend .

# Login to registry
docker login rg.nl-ams.scw.cloud/ash-backend -u nologin -p $SCW_SECRET_KEY

# Tag and push
docker tag ash-backend rg.nl-ams.scw.cloud/ash-backend/ash-backend:latest
docker push rg.nl-ams.scw.cloud/ash-backend/ash-backend:latest
```

## Custom Domain

To use a custom domain:

1. Set `domain` variable in `terraform.tfvars`:
   ```hcl
   domain = "relay.ashprotocol.app"
   ```

2. Apply terraform changes

3. Add CNAME record in your DNS:
   ```
   relay.ashprotocol.app -> <container-endpoint>
   ```

## Cost Optimization

- `container_min_scale = 0`: Scales to zero when idle (no cost)
- `container_max_scale = 5`: Limits maximum instances
- Serverless Containers are billed per 100ms of execution

## GitHub Actions Configuration

For CI/CD, add these secrets and variables to your repository:

### Secrets

| Secret | Description |
|--------|-------------|
| `SCW_ACCESS_KEY` | Scaleway access key |
| `SCW_SECRET_KEY` | Scaleway secret key |

### Variables (Repository Variables)

| Variable | Description |
|----------|-------------|
| `SCW_DEFAULT_PROJECT_ID` | Scaleway project ID |
| `SCW_DEFAULT_ORGANIZATION_ID` | Scaleway organization ID |

## Destroying Infrastructure

```bash
terraform destroy
```

**Warning**: This will delete all resources including the container registry and any stored images.
