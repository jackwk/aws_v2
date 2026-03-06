#!/bin/bash
# Update the system
sudo dnf update -y

# Install compilers and Git
sudo dnf install gcc clang git -y

# Download and install Zig
wget https://ziglang.org/download/0.13.0/zig-linux-aarch64-0.13.0.tar.xz
tar -xf zig-linux-aarch64-0.13.0.tar.xz
sudo mv zig-linux-aarch64-0.13.0 /usr/local/zig

# Update PATH for Zig
export PATH="/usr/local/zig:$PATH"
echo 'export PATH="/usr/local/zig:$PATH"' >> ~/.bashrc
zig version

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Install Cargo Lambda
curl -fsSL https://cargo-lambda.info/install.sh | sh
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Install Terraform
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo dnf install -y terraform