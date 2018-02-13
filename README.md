# CropCoin
Shell script to install a [Cropcoin Masternode](https://bitcointalk.org/index.php?topic=2863802.0) on a Linux server running Ubuntu 16.04. Use it on your own risk.  

***
## Installation:  

wget -q https://raw.githubusercontent.com/zoldur/CropCoin/master/cropcoin.sh  
bash cropcoin.sh
***

## Desktop wallet setup  

After the MN is up and running, you need to configure the desktop wallet accordingly. Here are the steps:  
1. Open the CropCoin Desktop Wallet.  
2. Go to RECEIVE and create a New Address: **MN1**  
3. Send **1000** CROP to **MN1**.  
4. Wait for 15 confirmations.  
5. Go to **Tools -> "Debug console"**  
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

## Usage:  

For security reasons **CropCoin** is installed under **cropcoin** user, hence you need to **su - cropcoin** before checking:    

```
su - cropcoin
cropcoind masternode status
cropcoind getinfo
```  
Also, if you want to check/start/stop **cropcoind** , run one of the following commands as **root**:
```
systemctl status cropcoind #To check the service is running  
systemctl start cropcoind #To start cropcoind service  
systemctl stop cropcoind #To stop cropcpoind service  
```


***

  
Any donation is highly appreciated  

**CROP**: cKH8Gea49ZtNLLV1Q4zcQaFY7K1uQ2ki5s  
**BTC**: 1BzeQ12m4zYaQKqysGNVbQv1taN7qgS8gY  
**ETH**: 0x39d10fe57611c564abc255ffd7e984dc97e9bd6d  
