#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

clear

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}" 
   exit 1
fi

if [ -n "$(pidof cropcoind)" ]; then
  echo -e "${GREEN}Cropcoind already running.${NC}"
  exit 1
fi

echo -e "Prepare the system to install Cropcoin master node."
apt-get update > /dev/null 2>&1
apt -y install software-properties-common > /dev/null 2>&1
echo -e "${GREEN}Adding bitcoin PPA repository"
apt-add-repository -y ppa:bitcoin/bitcoin > /dev/null 2>&1
apt-get update > /dev/null 2>&1
echo -e "Installing required packages, it may take some time to finish.${NC}"
apt install -y ld-essential software-properties-common autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev \
libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git wget pwgen curl libdb4.8-dev \
bsdmainutils libdb4.8++-dev libminiupnpc-dev lzip > /dev/null 2>&1
if [ "$?" -gt "0" ];
  then
    echo -e "${RED}Not all required packages were installed properly. Try to install them manually by running the following commands:${NC}\n"
    echo "apt-get update"
    echo "apt -y install software-properties-common"
    echo "apt-add-repository -y ppa:bitcoin/bitcoin"
    echo "apt-get update"
    echo "apt install -y ld-essential software-properties-common autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev \
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
make install
make check
cd -
rm -f gmp-6.1.2.tar.lz

git clone https://github.com/Cropdev/CropDev.git 
cd CropDev/src/secp256k1
./autogen.sh
./configure
make
./tests
make install
cd ..
make -f makefile.unix
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile cropcoin. Please investigate.${NC}"
  exit 1
fi
cp -a cropcoind /usr/local/bin
chown $CROPCOINUSER: /usr/local/bin/cropcoind

clear

echo -e "${GREEN}Prepare to configure and start Cropcoin Masternode.${NC}"
DEFAULTCROPCOINFOLDER="$CROPCOINHOME/.Cropcoin"
read -p "Configuration folder: " -i $DEFAULTCROPCOINFOLDER -e CROPCOINFOLDER
: ${CROPCOINFOLDER:=$DEFAULTCROPCOINFOLDER}

DEFAULTCROPCOINPORT=17720
read -p "CROPCOIN Port: " -i $DEFAULTCROPCOINPORT -e CROPCOINPORT
: ${CROPCOINPORT:=$DEFAULTCROPCOINPOR}

mkdir -p $CROPCOINFOLDER
RPCUSER=$(pwgen -s 8 1)
RPCPASSWORD=$(pwgen -s 15 1)
cat << EOF > $CROPCOINFOLDER/Cropcoin.conf
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
EOF
chown -R $CROPCOINUSER $CROPCOINFOLDER >/dev/null

sudo -u $CROPCOINUSER /usr/local/bin/cropcoind -conf=$CROPCOINFOLDER/cropcoin.conf -datadir=$CROPCOINFOLDER
sleep 5

if [ -z "$(pidof cropcoind)" ]; then
  echo -e "${RED}Cropcoind server couldn't start. Check /var/log/syslog for errors.{$NC}"
  exit 1
fi

CROPCOINLEKEY=$(sudo -u $CROPCOINUSER /usr/local/bin/cropcoind -conf=$CROPCOINFOLDER/cropcoin.conf -datadir=$CROPCOINFOLDER masternode genkey)

kill $(pidof cropcoind)

sed -i 's/daemon=1/daemon=0/' $CROPCOINFOLDER/cropcoin.conf
NODEIP=$(curl -s4 icanhazip.com)
cat << EOF >> $CROPCOINFOLDER/cropcoin.conf
maxconnections=256
masternode=1
masternodeaddr=$NODEIP
masternodeprivkey=$CROPCOINLEKEY
EOF
chown -R $CROPCOINUSER: $CROPCOINFOLDER >/dev/null

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


FWSTATUS=$(ufw status 2>/dev/null|awk '/^Status:/{print $NF}')
if [ "$FWSTATUS" = "active" ]; then
  echo -e "Setting up firewall to allow ingress on port ${GREEN}$CROPCOINPORT${NC}"
  ufw allow $CROPCOINPORT/tcp comment "Cropcoin MN port" >/dev/null
fi

systemctl daemon-reload
systemctl start cropcoind.service
systemctl enable cropcoind.service


if [[ -z $(pidof cropcoind) ]]; then
  echo -e "${RED}Cropcoind is not running${NC}, please investigate. You should start by running the following commands:"
  echo "systemctl start cropcoind.service"
  echo "systemctl status cropcoind.service"
  echo "less /var/log/syslog"
  exit 1 
fi

echo
echo -e "======================================================================================================================="
echo -e "Cropcoin Masternode is up and running as user ${GREEN}$CROPCOINUSER${NC} and it is listening on port ${GREEN}$CROPCOINPORT${NC}." 
echo -e "Configuration file is: ${RED}$CROPCOINFOLDER/Cropcoin.conf${NC}"
echo -e "MASTERNODE PRIVATEKEY is: ${RED}$CROPCOINLEKEY${NC}"
echo -e "========================================================================================================================"

