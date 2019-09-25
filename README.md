# iov

# Debug

`netstat -lnptu`
`sudo netstat -lnp`

`Kill -9 pid`

## Socket issue

`rm ${DIR_WORK}/iovns.sock`

## Run IOV node

`sudo /opt/iovns/bin/bnsd    -home=/home/iov/babynet    start    -bind=unix:///home/iov/babynet/iovns.sock    -min_fee '0.5 IOV'`

## Run Tendermint instance 

`sudo /opt/iovns/bin/tendermint node --home=/home/iov/babynet --proxy_app=unix:///home/iov/babynet/iovns.sock --consensus.create_empty_blocks=false --moniker='Stake Capital' --p2p.laddr=tcp://0.0.0.0:16656 --p2p.seeds=6cfa2e2f28602fe4779031ce6dc91a9e75ba764d@35.246.220.157:26656,0aa87eb8990603df79914c894a3165cf70880883@35.246.252.171:26656 --rpc.laddr=tcp://127.0.0.1:16657 --rpc.unsafe=false`


## Check log

`journalctl -f | grep iovns`
