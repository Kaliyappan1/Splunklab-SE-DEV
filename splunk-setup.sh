#!/bin/bash

# Install Required Packages
yum install -y wget tar

# Create Splunk User and Directory (if not exists)
id -u splunk &>/dev/null || useradd splunk
mkdir -p /opt/splunk
chown -R splunk:splunk /opt/splunk

# Switch to Splunk user and execute setup commands
su - splunk <<'EOF'
# Navigate to home directory
cd /home/splunk

# Download and Extract Splunk
wget -O splunk-9.4.1-linux-amd64.tgz "https://download.splunk.com/products/splunk/releases/9.4.1/linux/splunk-9.4.1-e3bdab203ac8-linux-amd64.tgz"
tar -xvf splunk-9.4.1-linux-amd64.tgz -C /opt/

# Navigate to Splunk bin directory and start Splunk
/opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt --seed-passwd 'admin123'
EOF

# Stop Splunk before enabling boot-start
/opt/splunk/bin/splunk stop

# Enable Splunk to start at boot (run as root)
/opt/splunk/bin/splunk enable boot-start -user splunk

# Start Splunk again (so it's running now)
/opt/splunk/bin/splunk start