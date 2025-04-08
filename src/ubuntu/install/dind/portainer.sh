#!/bin/bash
# Comprehensive Portainer startup script for Kasm that handles certutil installation
# Save as /dockerstartup/portainer.sh and make executable

echo "Starting Portainer service..."

# Function to check if a container exists and is running
container_is_running() {
    docker ps -q -f name="$1" | grep -q .
}

# Function to check if a container exists (running or not)
container_exists() {
    docker ps -a -q -f name="$1" | grep -q .
}

# Create portainer data volume if it doesn't exist
if ! docker volume inspect portainer_data > /dev/null 2>&1; then
    echo "Creating Portainer data volume..."
    docker volume create portainer_data
fi

# If the container exists but isn't running, try to start it
if container_exists "portainer" && ! container_is_running "portainer"; then
    echo "Found stopped Portainer container, starting it..."
    docker start portainer
    
# If the container doesn't exist, create a new one
elif ! container_exists "portainer"; then
    echo "Creating new Portainer container..."
    docker run -d -p 8000:8000 -p 9443:9443 --name=portainer --restart=always \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v portainer_data:/data \
      portainer/portainer-ee:sts
else
    echo "Portainer is already running."
fi

# Wait for Portainer to fully start before checking certificates
echo "Waiting for Portainer to initialize and generate certificates..."
sleep 10

# Function to add certificate to trust store if it exists
add_cert_to_trust_store() {
    PORTAINER_CERT_PATH="/var/lib/docker/volumes/portainer_data/_data/certs/cert.pem"
    
    if [ -f "$PORTAINER_CERT_PATH" ]; then
        echo "Found Portainer certificate, adding to trust stores..."
        
        # Create certificate directory if it doesn't exist
        mkdir -p /usr/local/share/ca-certificates/portainer/
        
        # Copy the certificate to the CA certificates directory
        cp "$PORTAINER_CERT_PATH" /usr/local/share/ca-certificates/portainer/portainer.crt
        
        # Update the CA certificates
        update-ca-certificates
        
        # Create a copy for the kasm-user
        mkdir -p /tmp/portainer-certs
        cp "$PORTAINER_CERT_PATH" /tmp/portainer-certs/portainer.crt
        chown -R kasm-user:kasm-user /tmp/portainer-certs
        
        # Make sure the NSS directory exists for kasm-user
        mkdir -p /home/kasm-user/.pki/nssdb
        chown -R kasm-user:kasm-user /home/kasm-user/.pki
        
        # Add to kasm-user's NSS database using certutil
        # First, ensure certutil is installed
        if ! command -v certutil &> /dev/null; then
            echo "Installing certutil (libnss3-tools)..."
            apt-get update && apt-get install -y libnss3-tools
        fi
        
        # Add certificate to NSS database as kasm-user
        echo "Adding certificate to kasm-user's NSS database with certutil..."
        sudo -u kasm-user certutil -d sql:/home/kasm-user/.pki/nssdb -A -t "P,," -n "Portainer" -i /tmp/portainer-certs/portainer.crt
        
        # Add for Firefox specifically if Firefox profile directory exists
        FIREFOX_DIR="/home/kasm-user/.mozilla/firefox"
        if [ -d "$FIREFOX_DIR" ]; then
            echo "Firefox profile detected, adding certificate there as well..."
            PROFILE_DIR=$(find "$FIREFOX_DIR" -name "*.default" -o -name "*.default-release" | head -n 1)
            
            if [ -n "$PROFILE_DIR" ]; then
                # Create cert DB if it doesn't exist
                if [ ! -f "$PROFILE_DIR/cert9.db" ]; then
                    sudo -u kasm-user mkdir -p "$PROFILE_DIR"
                    sudo -u kasm-user certutil -d "$PROFILE_DIR" -N --empty-password
                fi
                
                # Add certificate to Firefox profile
                sudo -u kasm-user certutil -d "$PROFILE_DIR" -A -t "P,," -n "Portainer" -i /tmp/portainer-certs/portainer.crt
            else
                echo "No Firefox profile found, skipping Firefox-specific certificate installation."
            fi
        fi
        
        echo "Certificate has been added to all relevant trust stores."
        return 0
    else
        echo "Portainer certificate not yet available at $PORTAINER_CERT_PATH"
        return 1
    fi
}

# Try to add the certificate initially
add_cert_to_trust_store

# Main loop for monitoring Portainer
echo "Entering monitoring loop for Portainer..."
while true; do
    # Check if Portainer is still running
    if ! container_is_running "portainer"; then
        echo "Portainer container stopped, attempting to restart..."
        
        # Try to start it if it exists but is stopped
        if container_exists "portainer"; then
            docker start portainer
        else
            # If it doesn't exist, create a new one
            docker run -d -p 8000:8000 -p 9443:9443 --name=portainer --restart=always \
              -v /var/run/docker.sock:/var/run/docker.sock \
              -v portainer_data:/data \
              portainer/portainer-ee:sts
        fi
        
        # Wait for container to initialize after restart
        sleep 10
    fi
    
    # Try to add certificate again if we haven't successfully added it yet
    if [ ! -f "/usr/local/share/ca-certificates/portainer/portainer.crt" ]; then
        add_cert_to_trust_store
    fi
    
    # Wait before checking again
    sleep 30
done