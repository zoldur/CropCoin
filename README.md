# CropCoin
Shell script to install a [Cropcoin Masternode](https://bitcointalk.org/index.php?topic=2863802.0) on a Linux server running Ubuntu 16.04. Use it on your own risk.  
***

## Installation for v1.1.0.0:
```
wget -q https://raw.githubusercontent.com/zoldur/CropCoin/master/cropcoin.sh
bash cropcoin.sh
```
***

## Desktop wallet setup  

After the MN is up and running, you need to configure the desktop wallet accordingly. Here are the steps:  
1. Open the CropCoin Desktop Wallet.  
2. Go to RECEIVE and create a New Address: **MN1**  
3. Send **2500** **500** or **10000** CROP to **MN1**.
4. Wait for 15 confirmations.  
5. Go to **Help -> "Debug Window - Console"**  
6. Type the following command: **masternode outputs**  
7. Go to **Masternodes** tab  
8. Click **Create** and fill the details:  
* Alias: **MN1**  
* Address: **VPS_IP:PORT**  
* Privkey: **Masternode Private Key**  
* TxHash: **First value from Step 6**  
* Output index:  **Second value from Step 6**  
* Reward address: leave blank  
* Reward %: leave blank  
9. Click **OK** to add the masternode  
10. Click **Start All**  
***

## Multiple MN on one VPS:

It is now possible to run multiple **CropCoin** Master Nodes on the same VPS. Each MN will run under a different user you will choose during installation.  
***

## Usage:

For security reasons **CropCoin** is installed under a normal user, usually **cropcoin**, hence you need to **su - cropcoin** before checking:  
```
CROPUSER=cropcoin #replace cropcoin with the MN username you want to check  
su - $CROPUSER
cropcoind masternode status  
cropcoind getinfo
```
Also, if you want to check/start/stop **cropcoin** daemon for a particular MN, run one of the following commands as **root**:
```
CROPUSER=cropcoin  #replace cropcoin with the MN username you want to check  
systemctl status $CROPUSER #To check the service is running  
systemctl start $CROPUSER #To start cropcoind service  
systemctl stop $CROPUSER #To stop cropcpoind service  
systemctl is-enabled $CROPUSER #To check cropcoind service is enabled on boot  
```
***

## Wallet re-sync

If you need to resync the wallet, run the following commands as **root**:
```
CROPUSER=cropcoin  #replace cropcoin with the MN username you want to resync
systemctl stop $CROPUSER
rm -r /home/$CROPUSER/.cropcoin/{banlist.dat,blk0001.dat,database,db.log,mncache.dat,peers.dat,smsgDB,smsg.ini,txleveldb}
systemctl start $CROPUSER
```
***

## Wallet update to 1.1.0.0
Run the following commands to update **CropCoin** to version **1.1.0.0**
```
for crop in $(grep -l cropcoind /etc/systemd/system/*.service | awk -F"/" '{print $NF}'); do systemctl stop $crop; done
rm cropcoind.gz
wget -q https://github.com/zoldur/CropCoin/releases/download/v1.1.0.0/cropcoind.gz
gunzip cropcoind.gz
chmod +x cropcoind
cp cropcoind /usr/local/bin
for crop in $(grep -l cropcoind /etc/systemd/system/*.service | awk -F"/" '{print $NF}'); do systemctl start $crop; done
```

## Donations:

Any donation is highly appreciated  

**CROP**: cKH8Gea49ZtNLLV1Q4zcQaFY7K1uQ2ki5s  
**BTC**: 3MNhbUq5smwMzxjU2UmTfeafPD7ag8kq76  
**ETH**: 0x26B9dDa0616FE0759273D651e77Fe7dd7751E01E  
**LTC**: LeZmPXHuQEhkd8iZY7a2zVAwF7DCWir2FF
