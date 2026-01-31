terraform {
  required_version = ">= 1.5.0"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.40"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  # State is stored per environment via -backend-config
  # Usage:
  #   terraform init -backend-config="key=scaleway/prod/terraform.tfstate"
  #   terraform init -backend-config="key=scaleway/beta/terraform.tfstate"
  backend "s3" {
    bucket                      = "ash-backend-tf-state"
    key                         = "scaleway/terraform.tfstate"  # Overridden by -backend-config
    region                      = "nl-ams"
    endpoint = "https://s3.nl-ams.scw.cloud"
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}

provider "scaleway" {
  zone   = var.zone
  region = var.region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
