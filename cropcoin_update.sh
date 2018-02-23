#!/bin/bash


TMP_FOLDER=$(mktemp -d)
CROP_REPO="https://github.com/Cropdev/CropDev.git"


RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

functions checks() {
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi
}

function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile $@. Please investigate.${NC}"
  exit 1
fi
}

function compile_new_wallet() {
  git clone $CROP_REPO $TMP_FOLDER
  cd $TMP_FOLDER/src
  mkdir obj/support
  mkdir obj/crypto
  make -f makefile.unix
  compile_error New Omega Wallet
 }

 function detect_and_stop_crop() {
 	for s in $(grep cropcoin /etc/systemd/system/*.service -l | awk -F"/" '{print $NF}'); do
 		systemctl stop $s
 	done
 }

function detect_and_start_crop() {
 	for s in $(grep cropcoin /etc/systemd/system/*.service -l | awk -F"/" '{print $NF}'); do
 		systemctl start $s
 	done
 }

 function backup_and_copy_wallet() {
 	cp -a /usr/local/bin/cropcoind /usr/local/bin/cropcoind.v1
 	cp -a $TMP_FOLDER/src/cropcoind /usr/local/bin
 }

checks
echo -e "${GREEN}Going to compile the new wallet, please grab a beer.${NC}"
compile_new_wallet
echo -e "${GREEN}New wallet compiled, going to stop cropcoin, replace the wallet and start it again${NC}"
detect_and_stop_crop
backup_and_copy_wallet
detect_and_start_crop
echo -e "${GREEN} New wallet version installed."

