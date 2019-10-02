#
# This file is based on IOV's official installation script provided here:
# https://docs.iov.one/docs/iov-name-service/validator/setup
# We have modified the script for Stake Capital's preferred user permissioning setup.
#

# Ensure that `curl`, `expr`, `grep`, `jq`, `sed`, and `wget` are all installed on the system.
# In the case of our default Stake Capital Ubuntu environment, the installation of `jq` is required:
sudo snap install jq

# Define key paths for use in the script
DIR_IOVNS=/opt/iovns/bin
DIR_WORK=/home/iov/boarnet

# Create all missing directories on both of the above paths
sudo mkdir -p $DIR_IOVNS
sudo mkdir -p $DIR_WORK

# Create the `iov` user
sudo useradd -m -d $DIR_IOVNS --system --shell /usr/sbin/nologin iov

# Ensure that the `iov` user has full privileges over both directories located at the aforementioned paths
sudo chown -R iov:iov $DIR_IOVNS
sudo chown -R iov:iov $DIR_WORK

sudo su # make life easier for the next ~100 lines

cd /etc/systemd/system

# create an environment file for the IOV Name Service services
cat <<__EOF_IOVNS_ENV__ > iovns.env
# directories (without spaces to ease pain)
DIR_IOVNS=/opt/iovns/bin
DIR_WORK=/home/iov/boarnet

# images
IMAGE_IOVNS=https://github.com/iov-one/weave/releases/download/v0.21.0/bnsd-0.21.0-linux-amd64.tar.gz
IMAGE_IOVNS_OPTS="-min_fee '0.5 IOV'"
IMAGE_TM=https://github.com/iov-one/tendermint-build/releases/download/v0.31.5-iov2/tendermint-0.31.5-linux-amd64.tar.gz
IMAGE_TM_OPTS="\
--moniker='moniker' \
--p2p.laddr=tcp://0.0.0.0:16656 \
--p2p.persistent_peers=96d70db6a08e194a7ae64b525cb8d1287fe922db@104.155.68.141:26656 \
--rpc.laddr=tcp://0.0.0.0:16657 \
--rpc.unsafe=false \
"

# socket
SOCK_TM=iovns.sock

# uid/gid
IOV_GID=$(id iov -g)
IOV_UID=$(id iov -u)
__EOF_IOVNS_ENV__

chgrp iov iovns.env
chmod g+r iovns.env

set -o allexport ; source /etc/systemd/system/iovns.env ; set +o allexport # pick-up env vars

# create iovns.service
cat <<'__EOF_IOVNS_SERVICE__' | sed -e 's@__DIR_IOVNS__@'"$DIR_IOVNS"'@g' > iovns.service
[Unit]
Description=IOV Name Service
After=network-online.target

[Service]
Type=simple
User=iov
Group=iov
EnvironmentFile=/etc/systemd/system/iovns.env
ExecStart=__DIR_IOVNS__/bnsd \
   -home=${DIR_WORK} \
   start \
   -bind=unix://${DIR_WORK}/${SOCK_TM} \
   $IMAGE_IOVNS_OPTS
LimitNOFILE=4096
#Restart=on-failure
#RestartSec=3
StandardError=journal
StandardOutput=journal
SyslogIdentifier=iovns

[Install]
WantedBy=multi-user.target
__EOF_IOVNS_SERVICE__

# create iovns-tm.service
cat <<'__EOF_IOVNS_TM_SERVICE__' | sed -e 's@__DIR_IOVNS__@'"$DIR_IOVNS"'@g' > iovns-tm.service
[Unit]
Description=Tendermint for IOV Name Service
After=iovns.service

[Service]
Type=simple
User=iov
Group=iov
EnvironmentFile=/etc/systemd/system/iovns.env
ExecStart=__DIR_IOVNS__/tendermint node \
   --home=${DIR_WORK} \
   --proxy_app=unix://${DIR_WORK}/${SOCK_TM} \
   $IMAGE_TM_OPTS
LimitNOFILE=4096
#Restart=on-failure
#RestartSec=3
StandardError=journal
StandardOutput=journal
SyslogIdentifier=iovns-tm

[Install]
WantedBy=multi-user.target
__EOF_IOVNS_TM_SERVICE__

# hack around ancient versions of systemd
expr $(systemctl --version | grep -m 1 -P -o "\d+") '<' 239 && {
   sed --in-place 's!\$IMAGE_IOVNS_OPTS!'"$IMAGE_IOVNS_OPTS"'!' /etc/systemd/system/iovns.service
   sed --in-place 's!\$IMAGE_TM_OPTS!\'"$IMAGE_TM_OPTS"'!' /etc/systemd/system/iovns-tm.service
}

systemctl daemon-reload

# download gitian built binaries; bnsd is the IOV Name Service daemon
mkdir -p ${DIR_IOVNS} && cd ${DIR_IOVNS}
wget ${IMAGE_IOVNS} && sha256sum bnsd*.gz       | fgrep 5b4ac76b4c0a06afdcd36687cec0352f33f46e41a60f61cdf7802225ed5ba1e8 && tar xvf bnsd*.gz || echo "BAD BINARY!"
wget ${IMAGE_TM}    && sha256sum tendermint*.gz | fgrep 421548f02dadca48452375b5905fcb49a267981b537c143422dde0591e46dc93 && tar xvf tendermint*.gz || echo "BAD BINARY!"

exit # root

# Pick-up env vars
sudo -H -u iov bash -c 'set -o allexport ; source /etc/systemd/system/iovns.env ; set +o allexport # pick-up env vars'

# Move back to DIR_WORK directory
cd ${DIR_WORK}

# Initialize tendermint
sudo -u iov ${DIR_IOVNS}/tendermint init --home=${DIR_WORK}
sudo -u iov curl --fail https://rpc.boarnet.iov.one/genesis | jq '.result.genesis' | sudo -u iov tee config/genesis.json
[[ ~/node_key.json ]] && sudo -u iov cp -av ~/node_key.json config
[[ ~/priv_validator_key.json ]] && sudo -u iov cp -av ~/priv_validator_key.json config
sudo -u iov sed --in-place 's!^timeout_commit.*!timeout_commit = "5s"!' config/config.toml

# Initialize IOV Name Service (bnsd)
sudo -u iov ${DIR_IOVNS}/bnsd -home=${DIR_WORK} init -i | sudo -u iov grep initialised

# Start the services
sudo systemctl start iovns.service
sudo systemctl start iovns-tm.service

# Watch the chain sync
journalctl -f -u iov
