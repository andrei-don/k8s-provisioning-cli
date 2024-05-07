#!/usr/bin/env bash
set -euo pipefail

#Setting this command twice because there are intermitent cases when the worker generates 2 CSRs, needs further investigation.
kubectl get csr --no-headers | awk '{print $1}' | xargs -I {} kubectl certificate approve {}
kubectl get csr --no-headers | awk '{print $1}' | xargs -I {} kubectl certificate approve {}