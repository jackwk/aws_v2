#!/bin/bash
# Redirect all output to a custom log file
exec > /var/log/user-data-setup.log 2>&1
# Print each command before executing it (great for debugging)
set -x 

# Update the system
sudo dnf update -y

# Install compilers and Git
sudo dnf install gcc clang git -y

# Download and install Zig
wget https://ziglang.org/download/0.13.0/zig-linux-aarch64-0.13.0.tar.xz
tar -xf zig-linux-aarch64-0.13.0.tar.xz
sudo mv zig-linux-aarch64-0.13.0 /usr/local/zig

# Update PATH for Zig globally so all users (including ec2-user) can use it
echo 'export PATH="/usr/local/zig:$PATH"' | sudo tee /etc/profile.d/zig.sh

# Install Rust specifically for the ec2-user
sudo -u ec2-user curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sudo -u ec2-user sh -s -- -y

# Install Cargo Lambda specifically for the ec2-user
# We wrap this in a bash command so we can source the newly installed Rust environment first
sudo -u ec2-user bash -c 'source $HOME/.cargo/env && curl -fsSL https://cargo-lambda.info/install.sh | sh'

# Install Terraform
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo dnf install -y terraform