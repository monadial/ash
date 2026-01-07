terraform {
  required_version = ">= 1.5.0"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.40"
    }
  }

  # Uncomment to use remote state (recommended for production)
  # backend "s3" {
  #   bucket                      = "ash-terraform-state"
  #   key                         = "scaleway/terraform.tfstate"
  #   region                      = "fr-par"
  #   endpoint                    = "s3.fr-par.scw.cloud"
  #   skip_credentials_validation = true
  #   skip_region_validation      = true
  #   skip_requesting_account_id  = true
  # }
}

provider "scaleway" {
  zone   = var.zone
  region = var.region
}
