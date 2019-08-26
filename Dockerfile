FROM alpine

ARG CONTAINER_UID=8730
ARG CONTAINER_GID=8730

ENV VOLUME_PATH=/usr/local/apache2/htdocs \
    AUTHORIZED_KEYS_FILE=/authorized_keys \
    CONTAINER_USER=rsync                  \
    CONTAINER_GROUP=rsync                 

# Alpine
# shadow: for groupmod and usermod
RUN apk add --no-cache --virtual .run-deps \
    shadow \
    bash \
    rsync openssh rssh \
    tzdata curl

# Default environment variables
ENV TZ="Asia/Ho_Chi_Minh" \
    LANG="C.UTF-8"

# RUN apt-get update && apt-get install -y \
#     openssh-server \
#     rsync \
#     && apt-get clean \
#     && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Alpine: Setup user & group, will be modified when run
RUN set -x \
    && addgroup -g $CONTAINER_GID ${CONTAINER_GROUP} \
    && adduser -u $CONTAINER_UID                     \
		-h $VOLUME_PATH                              \
		-S -s /usr/bin/rssh                          \
		-G $CONTAINER_GROUP                          \
        $CONTAINER_USER                              \
    && mkdir -p "$VOLUME_PATH"                       \
    && chown $CONTAINER_UID "$VOLUME_PATH"           \
    && touch $AUTHORIZED_KEYS_FILE                   \
    && chown $CONTAINER_UID $AUTHORIZED_KEYS_FILE    \
    && chmod 0400 $AUTHORIZED_KEYS_FILE

# Setup SSHD #################################
# https://docs.docker.com/engine/examples/running_ssh_service/
EXPOSE 22

# Setup AUTHORIZED_KEYS_FILE
RUN mkdir /var/run/sshd \
    && chmod 0755 /var/run/sshd \
    && echo "AuthorizedKeysFile $AUTHORIZED_KEYS_FILE" >>/etc/ssh/sshd_config \
    && echo "KexAlgorithms curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,diffie-hellman-group-exchange-sha256,diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1,diffie-hellman-group1-sha1" >>/etc/ssh/sshd_config \
    && echo "HostKeyAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,ssh-rsa,ssh-dss" >>/etc/ssh/sshd_config \
    && sed -i 's/.*PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/.*PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# SSH login fix. Otherwise user is kicked off after login
# FROM ubuntu:16.04
# RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

ENV NOTVISIBLE "in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile
# SSHD END #################################

# Setup rsync
EXPOSE 873

RUN echo "allowscp" >> /etc/rssh.conf \
    && echo "allowsftp" >> /etc/rssh.conf \
    && echo "allowrsync" >> /etc/rssh.conf

CMD ["rsync_server"]
ENTRYPOINT ["/entrypoint.sh"]
COPY entrypoint.sh /entrypoint.sh
COPY pipework /usr/bin/pipework
RUN chmod 744 /entrypoint.sh
