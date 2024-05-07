#!/usr/bin/env bash
set -euo pipefail

echo "Enabling kubectl autocompletion..."
sudo apt-get install bash-completion >/dev/null
echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'alias k="kubectl"' >>~/.bashrc
echo 'alias kn="kubectl config set-context --current --namespace"' >>~/.bashrc
echo 'complete -F __start_kubectl k' >>~/.bashrc
source ~/.bashrc