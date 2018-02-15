#!/bin/bash

TMP_FOLDER=$(mktemp -d)
USER_PASS=$(pwgen -s 10 1)
CONFIG_FILE="cropcoin.conf"
BINARY_FILE="/usr/local/bin/cropcoind"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'


function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile $@. Please investigate.${NC}"
  exit 1
fi
}


function checks() {
if [[ $(lsb_release -d) != *16.04* ]]; then
  echo -e "${RED}You are not running Ubuntu 16.04. Installation is cancelled.${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi

if [ -n "$(pidof cropcoind)" ]; then
  echo -e "${GREEN}\c"
  read -e -p "Cropcoind is already running. Do you want to add another MN? [Y/N]" NEW_CROP
  echo -e "{NC}"
  clear
else
  NEW_CROP="new"
fi
}

function prepare_system() {

echo -e "Prepare the system to install Cropcoin master node."
apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
apt install -y software-properties-common >/dev/null 2>&1
echo -e "${GREEN}Adding bitcoin PPA repository"
apt-add-repository -y ppa:bitcoin/bitcoin >/dev/null 2>&1
echo -e "Installing required packages, it may take some time to finish.${NC}"
apt-get update >/dev/null 2>&1
apt-get install -y make software-properties-common build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev \
libboost-filesystem-dev libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git \
wget pwgen curl libdb4.8-dev bsdmainutils libdb4.8++-dev libminiupnpc-dev libgmp3-dev 
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
bsdmainutils libdb4.8++-dev libminiupnpc-dev libgmp3-dev"
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
  echo -e "Clone git repo and compile it. This may take some time. Press a key to continue."
  read -n 1 -s -r -p ""

  cd $TMP_FOLDER
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
  cp -a cropcoind $BINARY_FILE
  clear
}

function enable_firewall() {
  FWSTATUS=$(ufw status 2>/dev/null|awk '/^Status:/{print $NF}')
  if [ "$FWSTATUS" = "active" ]; then
    echo -e "Setting up firewall to allow ingress on port ${GREEN}$CROPCOINPORT${NC}"
    ufw allow $CROPCOINPORT/tcp comment "Cropcoin MN port" >/dev/null
  fi
}

function systemd_cropcoin() {
  cat << EOF > /etc/systemd/system/$CROPCOINUSER.service
[Unit]
Description=Cropcoin service
After=network.target

[Service]
ExecStart=$BINARY_FILE -conf=$CROPCOINFOLDER/$CONFIG_FILE -datadir=$CROPCOINFOLDER
ExecStop=$BINARY_FILE -conf=$CROPCOINFOLDER/$CONFIG_FILE -datadir=$CROPCOINFOLDER stop
Restart=on-abort
User=$CROPCOINUSER
Group=$CROPCOINUSER
  
[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $CROPCOINUSER.service
  systemctl enable $CROPCOINUSER.service

  if [[ -z $(pidof cropcoind) ]]; then
    echo -e "${RED}Cropcoind is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo "systemctl start $CROPCOINUSER.service"
    echo "systemctl status $CROPCOINUSER.service"
    echo "less /var/log/syslog"
    exit 1
  fi
}

function ask_port() {
DEFAULTCROPCOINPORT=17720
read -p "CROPCOIN Port: " -i $DEFAULTCROPCOINPORT -e CROPCOINPORT
: ${CROPCOINPORT:=$DEFAULTCROPCOINPORT}
}

function ask_user() {
  DEFAULTCROPCOINUSER="cropcoin"
  read -p "Cropcoin user: " -i $DEFAULTCROPCOINUSER -e CROPCOINUSER
  : ${CROPCOINUSER:=$DEFAULTCROPCOINUSER}

  if [ -z "$(getent passwd $CROPCOINUSER)" ]; then
    useradd -m $CROPCOINUSER
    echo "$CROPCOINUSER:$USER_PASS" | chpasswd

    CROPCOINHOME=$(sudo -H -u $CROPCOINUSER bash -c 'echo $HOME')
    DEFAULTCROPCOINFOLDER="$CROPCOINHOME/.cropcoin"
    read -p "Configuration folder: " -i $DEFAULTCROPCOINFOLDER -e CROPCOINFOLDER
    : ${CROPCOINFOLDER:=$DEFAULTCROPCOINFOLDER}
    mkdir -p $CROPCOINFOLDER
    chown -R $CROPCOINUSER: $CROPCOINFOLDER >/dev/null
  else
    clear
    echo -e "${RED}User exits. Please enter another username: ${NC}"
    ask_user
  fi
}

function check_port() {
  declare -a PORTS
  PORTS=($(netstat -tnlp | awk '/LISTEN/ {print $4}' | awk -F":" '{print $NF}' | sort | uniq | tr '\r\n'  ' '))
  ask_port

  while [[ ${PORTS[@]} =~ $CROPCOINPORT ]] || [[ ${PORTS[@]} =~ $[CROPCOINPORT+1] ]]; do
    clear
    echo -e "${RED}Port in use, please choose another port:${NF}"
    ask_port
  done
}

function create_config() {
  RPCUSER=$(pwgen -s 8 1)
  RPCPASSWORD=$(pwgen -s 15 1)
  cat << EOF > $CROPCOINFOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
rpcport=$[CROPCOINPORT+1]
listen=1
server=1
daemon=1
port=$CROPCOINPORT
EOF
}

function create_key() {
  echo -e "Enter your ${RED}Masternode Private Key${NC}. Leave it blank to generate a new ${RED}Masternode Private Key${NC} for you:"
  read -e CROPCOINKEY
  if [[ -z "$CROPCOINKEY" ]]; then
  sudo -u $CROPCOINUSER /usr/local/bin/cropcoind -conf=$CROPCOINFOLDER/$CONFIG_FILE -datadir=$CROPCOINFOLDER
  sleep 5
  if [ -z "$(pidof cropcoind)" ]; then
   echo -e "${RED}Cropcoind server couldn't start. Check /var/log/syslog for errors.{$NC}"
   exit 1
  fi
  CROPCOINKEY=$(sudo -u $CROPCOINUSER $BINARY_FILE -conf=$CROPCOINFOLDER/$CONFIG_FILE -datadir=$CROPCOINFOLDER masternode genkey)
  sudo -u $CROPCOINUSER $BINARY_FILE -conf=$CROPCOINFOLDER/$CONFIG_FILE -datadir=$CROPCOINFOLDER stop
fi
}

function update_config() {
  sed -i 's/daemon=1/daemon=0/' $CROPCOINFOLDER/$CONFIG_FILE
  NODEIP=$(curl -s4 icanhazip.com)
  cat << EOF >> $CROPCOINFOLDER/$CONFIG_FILE
logtimestamps=1
maxconnections=256
masternode=1
masternodeaddr=$NODEIP
masternodeprivkey=$CROPCOINKEY
EOF
  chown -R $CROPCOINUSER: $CROPCOINFOLDER >/dev/null
}

function important_information() {
 echo
 echo -e "================================================================================================================================"
 echo -e "Cropcoin Masternode is up and running as user ${GREEN}$CROPCOINUSER${NC} and it is listening on port ${GREEN}$CROPCOINPORT${NC}."
 echo -e "${GREEN}$CROPCOINUSER${NC} password is ${RED}$USER_PASS${NC}"
 echo -e "Configuration file is: ${RED}$CROPCOINFOLDER/$CONFIG_FILE${NC}"
 echo -e "Start: ${RED}systemctl start $CROPCOINUSER.service${NC}"
 echo -e "Stop: ${RED}systemctl stop $CROPCOINUSER.service${NC}"
 echo -e "VPS_IP:PORT ${RED}$NODEIP:$CROPCOINPORT${NC}"
 echo -e "MASTERNODE PRIVATEKEY is: ${RED}$CROPCOINKEY${NC}"
 echo -e "================================================================================================================================"
}

function setup_node() {
  ask_user
  check_port
  create_config
  create_key
  update_config
  enable_firewall
  systemd_cropcoin
  important_information
}


##### Main #####
clear

checks
if [[ ("$NEW_CROP" == "y" || "$NEW_CROP" == "Y") ]]; then
  setup_node
  exit 0
elif [[ "$NEW_CROP" == "new" ]]; then
  prepare_system
  compile_cropcoin
  setup_node
else
  echo -e "${GREEN}Cropcoind already running.${NC}"
  exit 0
fi

