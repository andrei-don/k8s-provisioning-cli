#!/usr/bin/env bash
set -euo pipefail
cat /tmp/hostentries | sudo tee -a /etc/hosts >/dev/null