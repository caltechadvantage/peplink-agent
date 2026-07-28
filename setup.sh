#!/usr/bin/env bash

cur_dir="$( cd "$(dirname "$0")" ; pwd -P )"
user="$(id -u -n)"

# Load fleet/device settings (DTS_NGROK_AUTHTOKEN, etc.) if present.
# .env is gitignored; vars are passed explicitly to the sudo'd ngrok
# step below (sudo -E is rejected by default Pi sudoers).
if [ -f "${cur_dir}/.env" ]; then
    set -a; . "${cur_dir}/.env"; set +a
    echo "Loaded ${cur_dir}/.env"
fi

ROUTER_TYPE=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --type)
            if [[ -n "$2" && "$2" != --* ]]; then
                ROUTER_TYPE="$2"
                shift 2
            else
                echo "Error: --type requires a value (e.g., cradlepoint)"
                exit 1
            fi
            ;;
        *)
            echo "Unknown parameter passed: $1"
            exit 1
            ;;
    esac
done
if [[ -n "$ROUTER_TYPE" ]]; then
    echo "ROUTER_TYPE = \"$ROUTER_TYPE\"" > local_settings.py
fi

echo "Setting up Router Monitoring Application (${ROUTER_TYPE})"

sudo apt update -y
sudo apt install -y libtiff-dev libwebp-dev python3-dev

# Installing mongodb
wget -qO - https://www.mongodb.org/static/pgp/server-4.4.asc | sudo apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.4.list
sudo apt update -y
sudo apt install -y mongodb-org
sudo systemctl enable mongod
sudo systemctl start mongod

sudo pip3 install --break-system-packages -U pip
sudo pip3 install --break-system-packages -r requirements.txt

# Clear desktop and install splash video/screen
bash ${cur_dir}/scripts/clear_desktop.sh
bash ${cur_dir}/scripts/install_splash.sh

# Enable I2C
echo "dtparam=i2c_arm=on" | sudo tee -a /boot/firmware/config.txt

# Disable virtual keyboard
sudo raspi-config nonint do_squeekboard S3

# Enable Auto Start
sudo apt install -y screen
sudo cp ${cur_dir}/scripts/pl_start.sh /opt/
sudo sed -i -- "s/DIR/${cur_dir////\\/}/g" /opt/pl_start.sh
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/pl.desktop <<EOL
[Desktop Entry]
Type=Application
Exec=bash /opt/pl_start.sh
EOL

# Remote access (ngrok + ttyd + wayvnc/noVNC) — installs only when
# an authtoken is in .env. Same idempotent script the Starlink build
# uses, ported here so a Peplink5 unit can be remotely shelled into
# from the DTS dashboard without paying for Raspberry Pi Connect.
if [ -n "${DTS_NGROK_AUTHTOKEN:-}" ]; then
    if [ -f "${cur_dir}/scripts/setup_ngrok.sh" ]; then
        echo "Setting up ngrok remote access..."
        sudo DTS_NON_INTERACTIVE=1 \
             DTS_NGROK_AUTHTOKEN="${DTS_NGROK_AUTHTOKEN}" \
             DTS_NGROK_PREFIX="${DTS_NGROK_PREFIX:-}" \
             DTS_SSH_TCP_ADDR="${DTS_SSH_TCP_ADDR:-}" \
             DTS_NGROK_DOMAIN="${DTS_NGROK_DOMAIN:-}" \
             DTS_ENABLE_SCREEN="${DTS_ENABLE_SCREEN:-}" \
             bash ${cur_dir}/scripts/setup_ngrok.sh
    else
        echo "scripts/setup_ngrok.sh not found - skipping remote access."
    fi
else
    echo "Skipping ngrok setup - add DTS_NGROK_AUTHTOKEN to ${cur_dir}/.env to enable."
fi
