#!/bin/bash
# EC2 user data for the Rust Lambda dev box (Amazon Linux 2023, arm64 / Graviton).
# Runs once as root at first boot. Progress: /var/log/user-data-setup.log
exec > /var/log/user-data-setup.log 2>&1
set -euxo pipefail

DEV_USER="ec2-user"
TERRAFORM_VERSION="1.17.2"   # pin; check https://releases.hashicorp.com/terraform/

# System update and build tools. Git is included.
dnf update -y
dnf install -y gcc gcc-c++ clang make git openssl-devel pkgconf-pkg-config python3-pip tar unzip jq

# Rust via rustup, installed for the dev user only
sudo -u "$DEV_USER" -i bash -c \
  "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal -c rustfmt -c clippy"

# Cargo Lambda from PyPI: the wheel bundles Zig, so no manual Zig download or version pin.
# (Fallback if PyPI is not reachable: `cargo install cargo-lambda`, slow, and Zig must be installed separately.)
sudo -u "$DEV_USER" -i bash -c "pip3 install --user cargo-lambda"

# Terraform: pinned binary from HashiCorp with checksum verification (arm64)
cd "$(mktemp -d)"
curl -fsSLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_arm64.zip"
curl -fsSLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS"
sha256sum -c --ignore-missing "terraform_${TERRAFORM_VERSION}_SHA256SUMS"
unzip -o "terraform_${TERRAFORM_VERSION}_linux_arm64.zip" terraform -d /usr/local/bin

# Record what was installed
sudo -u "$DEV_USER" -i bash -c 'source "$HOME/.cargo/env" && rustc --version && cargo --version && cargo lambda --version'
git --version
terraform version
echo "user-data setup finished OK"
