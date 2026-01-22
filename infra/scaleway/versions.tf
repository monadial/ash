terraform {
  required_version = ">= 1.5.0"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.40"
    }
  }

  backend "s3" {
    bucket                      = "ash-tf-state"
    key                         = "scaleway/terraform.tfstate"
    region                      = "nl-ams"
    endpoints = {
      s3 = "https://s3.nl-ams.scw.cloud"
    }
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
