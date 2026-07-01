# tested on rocky linux 9.7

# AWS CLI
# Install dependencies
sudo dnf install -y curl unzip

# Download the installer
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

# Unzip
unzip awscliv2.zip

# Install
sudo ./aws/install

# Verify
aws --version


# ----------------------------------------

# Check the latest release tag first
LATEST=$(curl -s https://api.github.com/repos/kubernetes-sigs/aws-iam-authenticator/releases/latest | grep tag_name | cut -d '"' -f4)
echo $LATEST

# Download using the correct versioned URL
curl -Lo aws-iam-authenticator \
  "https://github.com/kubernetes-sigs/aws-iam-authenticator/releases/download/${LATEST}/aws-iam-authenticator_${LATEST#v}_linux_amd64"

# Make executable and move to PATH
chmod +x aws-iam-authenticator
sudo mv aws-iam-authenticator /usr/local/bin/

# Verify
aws-iam-authenticator version
