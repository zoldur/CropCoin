#!/bin/bash

function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile $@. Please investigate.${NC}"
  exit 1
fi
}

function checks() {
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}" 
   exit 1
fi

if [ -n "$(pidof cropcoind)" ]; then
  echo -e "${GREEN}Cropcoind already running.${NC}"
  exit 1
fi
}

function prepare_system() {

echo -e "Prepare the system to install Cropcoin master node."
apt-get update >/dev/null 2>&1
apt install -y software-properties-common >/dev/null 2>&1
echo -e "${GREEN}Adding bitcoin PPA repository"
apt-add-repository -y ppa:bitcoin/bitcoin >/dev/null 2>&1
echo -e "Installing required packages, it may take some time to finish.${NC}"
apt-get update >/dev/null 2>&1
apt-get install -y make software-properties-common build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev \
libboost-filesystem-dev libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git \
wget pwgen curl libdb4.8-dev bsdmainutils libdb4.8++-dev libminiupnpc-dev lzip
clear
if [ "$?" -gt "0" ];
  then
    echo -e "${RED}Not all required packages were installed properly. Try to install them manually by running the following commands:${NC}\n"
    echo "apt-get update"
    echo "apt -y install software-properties-common"
    echo "apt-add-repository -y ppa:bitcoin/bitcoin"
    echo "apt-get update"
    echo "apt install -y make build-essential libtool software-properties-common autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev \
libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git pwgen curl libdb4.8-dev \
bsdmainutils libdb4.8++-dev libminiupnpc-dev lzip"
 exit 1
fi

clear
echo -e "Checking if swap space is needed."
PHYMEM=$(free -g|awk '/^Mem:/{print $2}')
if [ "$PHYMEM" -lt "2" ];
  then
    echo -e "${GREEN}Server is running with less than 2G of RAM, creating 2G swap file.${NC}"
    dd if=/dev/zero of=/swapfile bs=1024 count=2M
    chmod 600 /swapfile
    mkswap /swapfile
    swapon -a /swapfile
else
  echo -e "${GREEN}Server running with at least 2G of RAM, no swap needed.${NC}"
fi
clear
}


function compile_cropcoin() {

DEFAULTCROPCOINUSER="cropcoin"
read -p "Cropcoin user: " -i $DEFAULTCROPCOINUSER -e CROPCOINUSER
: ${CROPCOINUSER:=$DEFAULTCROPCOINUSER}
useradd -m $CROPCOINUSER >/dev/null
CROPCOINHOME=$(sudo -H -u $CROPCOINUSER bash -c 'echo $HOME')

echo -e "Clone git repo and compile it. This may take some time. Press a key to continue."
read -n 1 -s -r -p ""

wget -q https://gmplib.org/download/gmp/gmp-6.1.2.tar.lz
tar -xvf gmp-6.1.2.tar.lz
cd gmp-6.1.2
./configure
make
compile_error gmp
make install
make check
cd ..
rm -f gmp-6.1.2.tar.lz
clear

wget https://github.com/Cropdev/CropDev/archive/v1.0.0.1.tar.gz
tar -xvf v1.0.0.1.tar.gz
cd CropDev-1.0.0.1/src/secp256k1
chmod +x autogen.sh
./autogen.sh
./configure --enable-module-recovery
make

./tests
clear
cd ..
mkdir obj/support
mkdir obj/crypto
make -f makefile.unix
compile_error cropcoin
cp -a cropcoind /usr/local/bin
clear
}

function enable_firewall() {
FWSTATUS=$(ufw status 2>/dev/null|awk '/^Status:/{print $NF}')
if [ "$FWSTATUS" = "active" ]; then
  echo -e "Setting up firewall to allow ingress on port ${GREEN}$CROPCOINPORT${NC}"
  ufw allow $CROPCOINPORT/tcp comment "Cropcoin MN port" >/dev/null
fi
}

function systemd_crop() {

cat << EOF > /etc/systemd/system/cropcoind.service
[Unit]
Description=Cropcoin service
After=network.target
[Service]
ExecStart=/usr/local/bin/cropcoind -conf=$CROPCOINFOLDER/cropcoin.conf -datadir=$CROPCOINFOLDER
ExecStop=/usr/local/bin/cropcoind -conf=$CROPCOINFOLDER/cropcoin.conf -datadir=$CROPCOINFOLDER stop
Restart=on-abort
User=$CROPCOINUSER
Group=$CROPCOINUSER
[Install]
WantedBy=multi-user.target
EOF
}

##### Main #####
clear

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'


checks
prepare_system
compile_cropcoin


echo -e "${GREEN}Prepare to configure and start Cropcoin Masternode.${NC}"
DEFAULTCROPCOINFOLDER="$CROPCOINHOME/.cropcoin"
read -p "Configuration folder: " -i $DEFAULTCROPCOINFOLDER -e CROPCOINFOLDER
: ${CROPCOINFOLDER:=$DEFAULTCROPCOINFOLDER}
mkdir -p $CROPCOINFOLDER

RPCUSER=$(pwgen -s 8 1)
RPCPASSWORD=$(pwgen -s 15 1)
cat << EOF > $CROPCOINFOLDER/cropcoin.conf
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
EOF
chown -R $CROPCOINUSER $CROPCOINFOLDER >/dev/null


DEFAULTCROPCOINPORT=17720
read -p "CROPCOIN Port: " -i $DEFAULTCROPCOINPORT -e CROPCOINPORT
: ${CROPCOINPORT:=$DEFAULTCROPCOINPORT}

echo -e "Enter your ${RED}Masternode Private Key${NC}. Leave it blank to generate a new ${RED}Masternode Private Key${NC} for you:"
read -e CROPCOINKEY
if [[ -z "$CROPCOINKEY" ]]; then
 sudo -u $CROPCOINUSER /usr/local/bin/cropcoind -conf=$CROPCOINFOLDER/cropcoin.conf -datadir=$CROPCOINFOLDER
 sleep 5
 if [ -z "$(pidof cropcoind)" ]; then
   echo -e "${RED}Cropcoind server couldn't start. Check /var/log/syslog for errors.{$NC}"
   exit 1
 fi
 CROPCOINKEY=$(sudo -u $CROPCOINUSER /usr/local/bin/cropcoind -conf=$CROPCOINFOLDER/cropcoin.conf -datadir=$CROPCOINFOLDER masternode genkey)
 kill $(pidof cropcoind)
fi

sed -i 's/daemon=1/daemon=0/' $CROPCOINFOLDER/cropcoin.conf
NODEIP=$(curl -s4 icanhazip.com)
cat << EOF >> $CROPCOINFOLDER/cropcoin.conf
logtimestamps=1
maxconnections=256
masternode=1
port=$CROPCOINPORT
masternodeaddr=$NODEIP
masternodeprivkey=$CROPCOINKEY
EOF
chown -R $CROPCOINUSER: $CROPCOINFOLDER >/dev/null


systemd_crop
enable_firewall


systemctl daemon-reload
sleep 3
systemctl start cropcoind.service
systemctl enable cropcoind.service


if [[ -z $(pidof cropcoind) ]]; then
  echo -e "${RED}Cropcoind is not running${NC}, please investigate. You should start by running the following commands as root:"
  echo "systemctl start cropcoind.service"
  echo "systemctl status cropcoind.service"
  echo "less /var/log/syslog"
  exit 1 
fi

echo
echo -e "======================================================================================================================="
echo -e "Cropcoin Masternode is up and running as user ${GREEN}$CROPCOINUSER${NC} and it is listening on port ${GREEN}$CROPCOINPORT${NC}." 
echo -e "Configuration file is: ${RED}$CROPCOINFOLDER/cropcoin.conf${NC}"
echo -e "VPS_IP:PORT ${RED}$NODEIP:$CROPCOINPORT${NC}"
echo -e "MASTERNODE PRIVATEKEY is: ${RED}$CROPCOINKEY${NC}"
echo -e "========================================================================================================================"

