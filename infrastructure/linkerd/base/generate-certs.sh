#!/bin/bash
set -e

echo "======================================"
echo "Linkerd Certificate Generation"
echo "======================================"

# Function to install step-cli
install_step_cli() {
    echo "step CLI not found. Installing..."

    # Detect OS and architecture
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    # Map architecture names
    case "$ARCH" in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="armv7"
            ;;
        *)
            echo "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    # Install based on OS
    case "$OS" in
        darwin)
            echo "Installing step-cli via Homebrew..."
            if command -v brew &> /dev/null; then
                brew install step
            else
                echo "Homebrew not found. Installing step-cli manually..."
                install_step_cli_binary "$OS" "$ARCH"
            fi
            ;;
        linux)
            # Detect Linux distribution
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                DISTRO=$ID
            else
                DISTRO="unknown"
            fi

            case "$DISTRO" in
                ubuntu|debian)
                    echo "Installing step-cli via apt on $DISTRO..."
                    echo "Downloading step-cli package..."

                    # Download with verbose output
                    if ! wget --show-progress -O step-cli.deb "https://dl.smallstep.com/cli/docs-cli-install/latest/step-cli_${ARCH}.deb" 2>&1; then
                        echo "Error: Failed to download step-cli package"
                        echo "Falling back to binary installation..."
                        install_step_cli_binary "$OS" "$ARCH"
                        return
                    fi

                    echo "Installing package..."
                    # Install with noninteractive frontend to avoid prompts
                    if sudo DEBIAN_FRONTEND=noninteractive dpkg -i step-cli.deb 2>&1; then
                        echo "Successfully installed step-cli via apt"
                    else
                        echo "dpkg installation failed, attempting to fix dependencies..."
                        sudo apt-get install -f -y
                        if ! sudo dpkg -i step-cli.deb; then
                            echo "Error: Installation failed, falling back to binary installation..."
                            rm -f step-cli.deb
                            install_step_cli_binary "$OS" "$ARCH"
                            return
                        fi
                    fi
                    rm -f step-cli.deb
                    ;;
                fedora|rhel|centos|rocky|almalinux)
                    echo "Installing step-cli via rpm on $DISTRO..."
                    echo "Downloading step-cli package..."

                    if ! wget --show-progress -O step-cli.rpm "https://dl.smallstep.com/cli/docs-cli-install/latest/step-cli_${ARCH}.rpm" 2>&1; then
                        echo "Error: Failed to download step-cli package"
                        echo "Falling back to binary installation..."
                        install_step_cli_binary "$OS" "$ARCH"
                        return
                    fi

                    echo "Installing package..."
                    if sudo rpm -i step-cli.rpm 2>&1; then
                        echo "Successfully installed step-cli via rpm"
                    else
                        echo "Error: Installation failed, falling back to binary installation..."
                        rm -f step-cli.rpm
                        install_step_cli_binary "$OS" "$ARCH"
                        return
                    fi
                    rm -f step-cli.rpm
                    ;;
                arch|manjaro)
                    echo "Installing step-cli via AUR on $DISTRO..."
                    if command -v yay &> /dev/null; then
                        yay -S --noconfirm step-cli
                    elif command -v paru &> /dev/null; then
                        paru -S --noconfirm step-cli
                    else
                        echo "AUR helper not found. Installing binary manually..."
                        install_step_cli_binary "$OS" "$ARCH"
                    fi
                    ;;
                alpine)
                    echo "Installing step-cli via apk on $DISTRO..."
                    if ! sudo apk add --no-cache step-cli; then
                        echo "Error: apk installation failed, falling back to binary installation..."
                        install_step_cli_binary "$OS" "$ARCH"
                    fi
                    ;;
                *)
                    echo "Unsupported Linux distribution: $DISTRO"
                    echo "Installing step-cli binary manually..."
                    install_step_cli_binary "$OS" "$ARCH"
                    ;;
            esac
            ;;
        *)
            echo "Unsupported operating system: $OS"
            exit 1
            ;;
    esac
}

# Function to install step-cli binary directly
install_step_cli_binary() {
    local os=$1
    local arch=$2
    local version="latest"

    echo "Downloading step-cli binary for $os-$arch..."

    # Get latest version
    echo "Fetching latest version from GitHub..."
    STEP_VERSION=$(curl -s https://api.github.com/repos/smallstep/cli/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

    if [ -z "$STEP_VERSION" ]; then
        echo "Warning: Failed to fetch latest version. Using default..."
        STEP_VERSION="0.27.2"
    else
        echo "Latest version: $STEP_VERSION"
    fi

    DOWNLOAD_URL="https://github.com/smallstep/cli/releases/download/v${STEP_VERSION}/step_${os}_${STEP_VERSION}_${arch}.tar.gz"

    echo "Downloading from: $DOWNLOAD_URL"

    # Download and extract with error handling
    if ! curl -fsSL --progress-bar -o step.tar.gz "$DOWNLOAD_URL"; then
        echo "Error: Failed to download step-cli binary"
        echo "Please install manually from: https://smallstep.com/docs/step-cli/installation/"
        return 1
    fi

    echo "Extracting archive..."
    if ! tar -xzf step.tar.gz; then
        echo "Error: Failed to extract archive"
        rm -f step.tar.gz
        return 1
    fi

    # Verify binary exists
    if [ ! -f "step_${STEP_VERSION}/bin/step" ]; then
        echo "Error: Binary not found in extracted archive"
        rm -rf step.tar.gz "step_${STEP_VERSION}"
        return 1
    fi

    # Install to /usr/local/bin (requires sudo) or ~/bin (user install)
    echo "Installing step-cli..."
    if [ -w /usr/local/bin ]; then
        mv "step_${STEP_VERSION}/bin/step" /usr/local/bin/
        echo "✓ step-cli installed to /usr/local/bin/step"
    elif sudo -n true 2>/dev/null; then
        sudo mv "step_${STEP_VERSION}/bin/step" /usr/local/bin/
        echo "✓ step-cli installed to /usr/local/bin/step"
    else
        echo "No sudo access, installing to user directory..."
        mkdir -p "$HOME/bin"
        mv "step_${STEP_VERSION}/bin/step" "$HOME/bin/"
        export PATH="$HOME/bin:$PATH"
        echo "✓ step-cli installed to $HOME/bin/step"
        echo ""
        echo "IMPORTANT: Add the following to your ~/.bashrc or ~/.zshrc:"
        echo "  export PATH=\"\$HOME/bin:\$PATH\""
        echo ""
    fi

    # Cleanup
    rm -rf step.tar.gz "step_${STEP_VERSION}"
}

# Check if step CLI is installed
if ! command -v step &> /dev/null; then
    install_step_cli

    # Verify installation
    if ! command -v step &> /dev/null; then
        echo "Failed to install step-cli. Please install manually from: https://smallstep.com/docs/step-cli/installation"
        exit 1
    fi
fi

echo "step-cli version: $(step version)"
echo ""

# Create certificates directory
mkdir -p certs
cd certs

echo "Generating trust anchor certificate..."
step certificate create root.linkerd.cluster.local ca.crt ca.key \
  --profile root-ca --no-password --insecure \
  --not-after=87600h \
  --kty RSA --size 4096

echo "Generating issuer certificate..."
step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
  --profile intermediate-ca --not-after=8760h \
  --no-password --insecure \
  --ca ca.crt --ca-key ca.key \
  --kty RSA --size 4096

echo ""
echo "======================================"
echo "Certificates generated successfully!"
echo "======================================"
echo ""
echo "Files created in ./certs directory:"
echo "  - ca.crt (Trust Anchor Certificate)"
echo "  - ca.key (Trust Anchor Private Key)"
echo "  - issuer.crt (Issuer Certificate)"
echo "  - issuer.key (Issuer Private Key)"
echo ""
echo "Next steps:"
echo "1. Create Kubernetes secrets with these certificates"
echo "2. Update linkerd-certificates.yaml with the actual certificate contents"
echo ""
echo "Or apply directly to cluster:"
echo ""
echo "kubectl create namespace linkerd"
echo ""
echo "kubectl create secret tls linkerd-trust-anchor \\"
echo "  --cert=ca.crt \\"
echo "  --key=ca.key \\"
echo "  --namespace=linkerd"
echo ""
echo "kubectl create secret tls linkerd-identity-issuer \\"
echo "  --cert=issuer.crt \\"
echo "  --key=issuer.key \\"
echo "  --namespace=linkerd"
echo ""
echo "kubectl label secret linkerd-trust-anchor linkerd.io/control-plane-component=identity -n linkerd"
echo "kubectl label secret linkerd-identity-issuer linkerd.io/control-plane-component=identity -n linkerd"

cd ..
