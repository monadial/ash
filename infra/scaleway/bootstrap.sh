#!/bin/bash
# =============================================================================
# Bootstrap Script for Terraform State Bucket
# =============================================================================
#
# This script creates the S3 bucket used to store Terraform state.
# Run this once before using Terraform for the first time.
#
# Prerequisites:
#   - Scaleway CLI installed and configured
#   - SCW_ACCESS_KEY and SCW_SECRET_KEY environment variables set
#
# Usage:
#   ./bootstrap.sh
#
# =============================================================================

set -e

BUCKET_NAME="ash-tf-state"
REGION="nl-ams"

echo "Creating Terraform state bucket: ${BUCKET_NAME}"

# Create bucket using Scaleway CLI
scw object bucket create name="${BUCKET_NAME}" region="${REGION}"

echo "Enabling versioning on bucket..."
scw object bucket update name="${BUCKET_NAME}" region="${REGION}" versioning=enabled

echo "Bootstrap complete!"
echo ""
echo "The Terraform state bucket '${BUCKET_NAME}' has been created in ${REGION}."
echo "You can now run 'terraform init' to initialize the backend."
