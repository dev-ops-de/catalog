#!/bin/bash -ex
###############################################################################
METADATA_HOST=rancher-metadata.rancher.internal
METADATA_VERSION=2015-12-19
METADATA=$METADATA_HOST/$METADATA_VERSION
function metadata { echo $(curl -s $METADATA/$1); }
###############################################################################

PRINCIPAL=${PRINCIPAL:-root}
ZK_SERVICE=${ZK_SERVICE:-"mesos/zk"}
MESOS_SERVICE=${MESOS_SERVICE:="mesos/mesos"}

function zk_service {
  IFS='/' read -ra ZK <<< "$ZK_SERVICE"
  echo $(metadata stacks/${ZK[0]}/services/${ZK[1]}/$1)
}

if [ "$(zk_service containers)" == "Not found" ]; then
  echo "A zookeeper ensemble is required, but '$ZK_SERVICE' was not found."
  sleep 1 && exit 1
fi

function zk_container_primary_ip {
  IFS='=' read -ra c <<< "$1"
  echo $(zk_service containers/${c[1]}/primary_ip)  
}

function zk_hosts {
  ZK_STRING=
  for container in $(zk_service containers); do
    ip=$(zk_container_primary_ip $container)
    if [ "$ZK_STRING" == "" ]; then
      ZK_STRING=$ip:2181
    else
      ZK_STRING=$ZK_STRING,$ip:2181
    fi
  done
  echo ${ZK_STRING}
}

function mesos_stack {
  IFS='/' read -ra X <<< "$MESOS_SERVICE"
  echo ${X[0]}
}

function zk_string {
  echo zk://$(zk_hosts)/$(mesos_stack)
}

export CHRONOS_MASTER=$(zk_string)
export CHRONOS_ZK_HOSTS=$(zk_hosts)
export CHRONOS_ZK_PATH=/$(metadata self/stack/name)
export CHRONOS_MESOS_FRAMEWORK_NAME=$(metadata self/stack/name)

CMD="chronos run_jar"

# Parse environment variables
for k in `set | grep ^CHRONOS_ | cut -d= -f1`; do
    eval v=\$$k
    CMD="$CMD --`echo $k | cut -d_ -f2- | tr '[:upper:]' '[:lower:]'` $v"
done

### dunno how to use this ###
if [ -n "$SECRET" ]; then
    touch /tmp/secret
    chmod 600 /tmp/secret
    echo -n "$SECRET" > /tmp/secret
    CMD="$CMD --mesos_authentication_principal $PRINCIPAL --mesos_authentication_secret_file /tmp/secret"
fi
### / dunno how to use this ###

echo $CMD

if [ $# -gt 0 ]; then
    exec "$@"
fi

exec $CMD