#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
"${SCRIPT_DIR}/../../scripts/update-terraform.sh"
docker image pull hashicorp/terraform-mcp-server:0.4.0 || true

