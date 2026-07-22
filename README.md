# Peplink Router Monitor

### 1. Download the latest Raspberry Pi OS image and flash your micro SD card.

### 2. Installation

- Clone this repository

    ```shell script
    cd ~
    sudo apt update
    sudo apt install -y git
    git clone https://github.com/caltechadvantage/Peplink5
    ```
  
- Install everything on RPi

    ```shell script
    cd ~/Peplink5

    # For Peplink Router
    bash setup.sh
  
    # For CradlePoint Router
    bash setup.sh --type cradlepoint
    ```
- And reboot! :)

## Updating the project

```shell
cd ~/Peplink5
bash update.sh
```

And reboot.

## Build executable (Optional)

```shell
sudo pip3 install --break-system-packages pyinstaller
pyinstaller --clean --onefile --name=Peplink5 main.py
```
