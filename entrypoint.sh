#!/bin/bash
set -e

if [ ! -z "${WAIT_INT}" ]; then
  /usr/bin/pipework --wait -i ${WAIT_INT}
fi

# Defaults
VOLUME_PATH=${VOLUME_PATH:-/data}
# HOSTS_ALLOW=${HOSTS_ALLOW:-0.0.0.0/0}
HOSTS_ALLOW=${HOSTS_ALLOW:-192.168.0.0/16 172.16.0.0/12 127.0.0.1/32}
READ_ONLY=${READ_ONLY:-false}
CHROOT=${CHROOT:-no}
VOLUME_NAME=${VOLUME_NAME:-data}
CONTAINER_UID=${CONTAINER_UID:-8730}
CONTAINER_GID=${CONTAINER_GID:-8730}
USERNAME=${USERNAME:-rsync}
# PASSWORD=${PASSWORD:-rsync}

################################################################################
# INIT
################################################################################

# Ensure time is in sync with host
# see https://wiki.alpinelinux.org/wiki/Setting_the_timezone
if [ -n ${TZ} ] && [ -f /usr/share/zoneinfo/${TZ} ]; then
  ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime
  echo ${TZ} > /etc/timezone
fi

# Ensure VOLUME PATH exists
if [ ! -e $VOLUME_PATH ]; then
  mkdir -p /$VOLUME_PATH
fi

mkdir -p /root/.ssh
> /root/.ssh/authorized_keys
chmod go-rwx /root/.ssh/authorized_keys
# sed -i "s/#PasswordAuthentication yes/PasswordAuthentication no/g" /etc/ssh/sshd_config

# Provide CRON_TASK_* via environment variable
> /etc/crontabs/root
for item in `env`; do
  case "$item" in
    CRON_TASK*)
        ENVVAR=`echo $item | cut -d \= -f 1`
        printenv $ENVVAR >> /etc/crontabs/root
        echo "root" > /etc/crontabs/cron.update
        ;;
  esac
done

# Generate host SSH keys
if [ ! -e /etc/ssh/ssh_host_rsa_key.pub ]; then
  ssh-keygen -A
fi

# Generate root SSH key
if [ ! -e /root/.ssh/id_rsa.pub ]; then
  ssh-keygen -q -N "" -f /root/.ssh/id_rsa
fi


################################################################################
# START as SERVER
################################################################################

if [ "$1" = 'rsync_server' ]; then

  # if [ -e "/root/.ssh/authorized_keys" ]; then
  #   chmod 400 /root/.ssh/authorized_keys
  #   chown root:root /root/.ssh/authorized_keys
  # fi

  ################################################################################
  # START sshd
  ################################################################################

  # Copy authorized keys from ENV variable
  echo "$AUTHORIZED_KEYS" >$AUTHORIZED_KEYS_FILE

  # Prevent the user from changing directory upwards
  sed -i -e '/chrootpath/d' /etc/rssh.conf
  echo "chrootpath = $VOLUME_PATH" >> /etc/rssh.conf

  groupmod --non-unique --gid "$CONTAINER_GID" ${CONTAINER_GROUP}
  usermod --non-unique --home "$VOLUME_PATH" --shell /usr/bin/rssh --uid "$CONTAINER_UID" --gid "$CONTAINER_GID" "$CONTAINER_USER"
  # Chown data folder (if mounted as a volume for the first time)
  chown "${CONTAINER_USER}:${CONTAINER_GROUP}" "$VOLUME_PATH"
  chown "${CONTAINER_USER}:${CONTAINER_GROUP}" $AUTHORIZED_KEYS_FILE

  # Run sshd on container start
  # exec /usr/sbin/sshd -D -e &
  exec /usr/sbin/sshd &

  ################################################################################
  # Configure rsync
  ################################################################################

  # Grab UID of owner of the volume directory
  if [ -z $CONTAINER_UID ]; then
    CONTAINER_UID=$(stat -c '%u' $VOLUME_PATH)
  else
    echo "CONTAINER_UID is set forced to: $CONTAINER_UID"
  fi
  if [ -z $CONTAINER_GID ]; then
    CONTAINER_GID=$(stat -c '%g' $VOLUME_PATH)
  else
    echo "CONTAINER_GID is set forced to: $CONTAINER_GID"
  fi

  echo "root:$PASSWORD" | chpasswd

  # Generate password file
  if [ ! -z $PASSWORD ]; then
    echo "$USERNAME:$PASSWORD" >  /etc/rsyncd.secrets
    chmod 0400 /etc/rsyncd.secrets
  fi

  mkdir -p $VOLUME_PATH

  # Alternalte: generate configuration
  # eval "echo \"$(cat /rsyncd.tpl.conf)\"" > /etc/rsyncd.conf

  [ -f /etc/rsyncd.conf ] || cat <<EOF > /etc/rsyncd.conf
  # /etc/rsyncd.conf

  # Minimal configuration file for rsync daemon
  # See rsync(1) and rsyncd.conf(5) man pages for help

  # This line is required by the /etc/init.d/rsyncd script
  pid file = /var/run/rsyncd.pid
  
  uid = ${CONTAINER_UID}
  gid = ${CONTAINER_GID}
  use chroot = ${CHROOT}
  reverse lookup = no
  
  log file = /dev/stdout

  [${VOLUME_NAME}]
    uid = root
    gid = root
    hosts deny = *
    hosts allow = ${HOSTS_ALLOW}
    read only = ${READ_ONLY}
    path = ${VOLUME_PATH}
    comment = ${VOLUME_PATH} directory
    auth users = ${USERNAME}:rw
    secrets file = /etc/rsyncd.secrets
    timeout = 600
    transfer logging = true
EOF

  # Check if a script is available in /docker-entrypoint.d and source it
  # You can use it for example to create additional sftp users
  for f in /docker-entrypoint.d/*; do
    case "$f" in
      *.sh)  echo "$0: running $f"; . "$f" ;;
      *)     echo "$0: ignoring $f" ;;
    esac
  done

  # RUN rsync in no daemon and expose errors to stdout
  exec /usr/bin/rsync --no-detach --daemon --config /etc/rsyncd.conf "$@"
fi

echo "Please add this ssh key to your server /home/user/.ssh/authorized_keys        "
echo "================================================================================"
echo "`cat /root/.ssh/id_rsa.pub`"
echo "================================================================================"

################################################################################
# START as CLIENT via crontab
################################################################################

if [ "$1" == "client" ]; then
  exec /usr/sbin/crond -f
fi

################################################################################
# Anything else
################################################################################
exec "$@"
