#!/bin/bash

# command line arguments
WALLET="46mhgUXVwfVgT1AcofHVxb8dkNQfB14DeCGgvFPTs4CK5sYfzmUW2DUETDeV8mW8HM7Dxw2GgZHJgW6xkPd21icjDE1GCem"

# checking prerequisites

if [ -z $WALLET ]; then
  echo "ERROR: Please specify your wallet address"
  exit 1
fi

WALLET_BASE=`echo $WALLET | cut -f1 -d"."`
if [ ${#WALLET_BASE} != 106 -a ${#WALLET_BASE} != 95 ]; then
  echo "ERROR: Wrong wallet base address length (should be 106 or 95): ${#WALLET_BASE}"
  exit 1
fi

if [ -z $HOME ]; then
  echo "ERROR: Please define HOME environment variable to your home directory"
  exit 1
fi

if [ ! -d $HOME ]; then
  echo "ERROR: Please make sure HOME directory $HOME exists or set it yourself using this command:"
  echo '  export HOME=<dir>'
  exit 1
fi

if ! type curl >/dev/null; then
  echo "ERROR: This script requires \"curl\" utility to work correctly"
  exit 1
fi

# calculating port

CPU_THREADS=$(nproc)
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 700 / 1000))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "ERROR: Can't compute projected Monero CN hashrate"
  exit 1
fi

power2() {
  if ! type bc >/dev/null; then
    if   [ "$1" -gt "8192" ]; then
      echo "8192"
    elif [ "$1" -gt "4096" ]; then
      echo "4096"
    elif [ "$1" -gt "2048" ]; then
      echo "2048"
    elif [ "$1" -gt "1024" ]; then
      echo "1024"
    elif [ "$1" -gt "512" ]; then
      echo "512"
    elif [ "$1" -gt "256" ]; then
      echo "256"
    elif [ "$1" -gt "128" ]; then
      echo "128"
    elif [ "$1" -gt "64" ]; then
      echo "64"
    elif [ "$1" -gt "32" ]; then
      echo "32"
    elif [ "$1" -gt "16" ]; then
      echo "16"
    elif [ "$1" -gt "8" ]; then
      echo "8"
    elif [ "$1" -gt "4" ]; then
      echo "4"
    elif [ "$1" -gt "2" ]; then
      echo "2"
    else
      echo "1"
    fi
  else 
    echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l;
  fi
}

PORT=$(( $EXP_MONERO_HASHRATE * 30 ))
PORT=$(( $PORT == 0 ? 1 : $PORT ))
PORT=`power2 $PORT`
PORT=$(( 10000 + $PORT ))
if [ -z $PORT ]; then
  echo "ERROR: Can't compute port"
  exit 1
fi

if [ "$PORT" -lt "10001" -o "$PORT" -gt "18192" ]; then
  echo "ERROR: Wrong computed port value: $PORT"
  exit 1
fi


# printing intentions

echo "I will download, setup and run in background Monero CPU proxy."
echo "If needed, proxy in foreground can be started by $HOME/xmrig-proxy/proxy.sh script."
echo "Mining will happen to $WALLET wallet."
echo

if ! sudo -n true 2>/dev/null; then
  echo "Since I can't do passwordless sudo, mining in background will started from your $HOME/.profile file first time you login this host after reboot."
else
  echo "Mining in background will be performed using xmrig-proxy systemd service."
fi

echo
echo "JFYI: This host has $CPU_THREADS CPU threads, so projected Monero hashrate is around $EXP_MONERO_HASHRATE KH/s."
echo

# start doing stuff: preparing proxy

echo "[*] Downloading xmrig-proxy to /tmp/xmrig-proxy.tar.gz"
if ! curl -L --progress-bar "https://github.com/KANIKIG/my_xmrig_proxy/raw/main/xmrig-proxy.tar.gz" -o /tmp/xmrig-proxy.tar.gz; then
  echo "ERROR: Can't download https://github.com/KANIKIG/my_xmrig_proxy/raw/main/xmrig-proxy.tar.gz file to /tmp/xmrig-proxy.tar.gz"
  exit 1
fi

echo "[*] Unpacking /tmp/xmrig-proxy.tar.gz to $HOME/xmrig-proxy"
[ -d $HOME/xmrig-proxy ] || mkdir $HOME/xmrig-proxy
if ! tar xf /tmp/xmrig-proxy.tar.gz -C $HOME/xmrig-proxy; then
  echo "ERROR: Can't unpack /tmp/xmrig-proxy.tar.gz to $HOME/xmrig-proxy directory"
  exit 1
fi
rm /tmp/xmrig-proxy.tar.gz

echo "[*] My Proxy $HOME/xmrig-proxy/xmrig-proxy is OK"

PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
if [ "$PASS" == "localhost" ]; then
  PASS=`ip route get 1 | awk '{print $NF;exit}'`
fi
if [ -z $PASS ]; then
  PASS=na
fi

sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:'$PORT'",/' $HOME/moneroocean/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $HOME/xmrig-proxy/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/xmrig-proxy/config.json
sed -i 's#"log-file": *null,#"log-file": "'$HOME/xmrig-proxy/xmrig-proxy.log'",#' $HOME/xmrig-proxy/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $HOME/xmrig-proxy/config.json

cp $HOME/xmrig-proxy/config.json $HOME/xmrig-proxy/config_background.json
sed -i 's/"background": *false,/"background": true,/' $HOME/xmrig-proxy/config_background.json

# preparing script

echo "[*] Creating $HOME/xmrig-proxy/proxy.sh script"
cat >$HOME/xmrig-proxy/proxy.sh <<EOL
#!/bin/bash
if ! pidof xmrig-proxy >/dev/null; then
  nice $HOME/xmrig-proxy/xmrig-proxy \$*
else
  echo "Monero proxy is already running in the background. Refusing to run another one."
  echo "Run \"killall xmrig-proxy\" or \"sudo killall xmrig-proxy\" if you want to remove background proxy first."
fi
EOL

chmod +x $HOME/xmrig-proxy/proxy.sh

# preparing script background work and work under reboot

if ! sudo -n true 2>/dev/null; then
  if ! grep xmrig-proxy/proxy.sh $HOME/.profile >/dev/null; then
    echo "[*] Adding $HOME/xmrig-proxy/proxy.sh script to $HOME/.profile"
    echo "$HOME/xmrig-proxy/proxy.sh --config=$HOME/xmrig-proxy/config_background.json >/dev/null 2>&1" >>$HOME/.profile
  else 
    echo "Looks like $HOME/xmrig-proxy/proxy.sh script is already in the $HOME/.profile"
  fi
  echo "[*] Running proxy in the background (see logs in $HOME/xmrig-proxy/xmrig.log file)"
  /bin/bash $HOME/xmrig-proxy/proxy.sh --config=$HOME/xmrig-proxy/config_background.json >/dev/null 2>&1
else

  if ! type systemctl >/dev/null; then

    echo "[*] Running proxy in the background (see logs in $HOME/xmrig-proxy/xmrig-proxy.log file)"
    /bin/bash $HOME/xmrig-proxy/proxy.sh --config=$HOME/xmrig-proxy/config_background.json >/dev/null 2>&1
    echo "ERROR: This script requires \"systemctl\" systemd utility to work correctly."
    echo "Please move to a more modern Linux distribution or setup proxy activation after reboot yourself if possible."

  else

    echo "[*] Creating xmrig-proxy systemd service"
    cat >/tmp/xmrig-proxy.service <<EOL
[Unit]
Description=Monero proxy service

[Service]
ExecStart=$HOME/xmrig-proxy/xmrig-proxy --config=$HOME/xmrig-proxy/config.json
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL
    sudo mv /tmp/xmrig-proxy.service /etc/systemd/system/xmrig-proxy.service
    echo "[*] Starting xmrig-proxy systemd service"
    sudo killall xmrig-proxy 2>/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable xmrig-proxy.service
    sudo systemctl start xmrig-proxy.service
    echo "To see proxy service logs run \"sudo journalctl -u xmrig-proxy -f\" command"
  fi
fi

echo ""

echo "[*] Setup complete"