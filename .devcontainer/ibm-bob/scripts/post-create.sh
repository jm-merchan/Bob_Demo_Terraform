#!/bin/bash
set -euo pipefail

echo "=== IBM Bob Terraform environment setup ==="

if [ -z "${TFE_TOKEN:-}" ]; then
  echo "TFE_TOKEN is not set; skipping Terraform credential file"
else
  mkdir -p ~/.terraform.d
  umask 077
  printf '{\n  "credentials": {\n    "app.terraform.io": {\n      "token": "%s"\n    }\n  }\n}\n' "$TFE_TOKEN" > ~/.terraform.d/credentials.tfrc.json
  echo "Terraform credentials configured"
fi

if [ -f .pre-commit-config.yaml ]; then
  pre-commit install
fi

echo "=== Setup complete ==="

