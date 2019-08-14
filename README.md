## rsync-server

A `rsyncd`/`sshd` server in Docker. You know, for moving files.  Based on container by the same name by axiom.  Changes include switching to ubuntu:bionic for base, setting up as auto build, few tweaks on paths and names, addition of pipework for odd network needs.


### tl;dr

Start a server (both `sshd` and `rsyncd` are supported)

```
$ docker run \
    --name rsync-server \ # Name it
    -p 8000:873 \ # rsyncd port
    -p 9000:22 \ # sshd port
    -e USERNAME=user \ # rsync username
    -e PASSWORD=pass \ # rsync/ssh password
    -v /your/public.key:/root/.ssh/authorized_keys \ # your public key
    apnar/rsync-server
```

#### `rsyncd`

```
$ rsync -av /your/folder/ rsync://user@localhost:8000/data
Password: pass
sending incremental file list
./
foo/
foo/bar/
foo/bar/hi.txt

sent 166 bytes  received 39 bytes  136.67 bytes/sec
total size is 0  speedup is 0.00
```


#### `sshd`

Please note that you are connecting as the `root` and not the user specified in
the `USERNAME` variable. If you don't supply a key file you will be prompted
for the `PASSWORD`.

```
$ rsync -av -e "ssh -i /your/private.key -p 9000 -l root" /your/folder/ localhost:/data
sending incremental file list
./
foo/
foo/bar/
foo/bar/hi.txt

sent 166 bytes  received 31 bytes  131.33 bytes/sec
total size is 0  speedup is 0.00
```


### Advanced Usage

Variable options (on run)

* `USERNAME` - the `rsync` username. defaults to `user`
* `PASSWORD` - the `rsync` password. defaults to `pass`
* `VOLUME_PATH`   - the path for `rsync`. defaults to `/data`
* `HOSTS_ALLOW`    - space separated list of allowed sources. defaults to `192.168.0.0/16 172.16.0.0/12`.
* `WAIT_INT` - wait for this interface to appear before starting services, for use with pipeworks.


##### Simple server on port 873

```
$ docker run -p 873:873 apnar/rsync-server
```


##### Use a volume for the default `/data`

```
$ docker run -p 873:873 -v /your/folder:/data apnar/rsync-server
```

##### Set a username and password

```
$ docker run \
    -p 873:873 \
    -v /your/folder:/data \
    -e USERNAME=admin \
    -e PASSWORD=mysecret \
    apnar/rsync-server
```

##### Run on a custom port

```
$ docker run \
    -p 9999:873 \
    -v /your/folder:/data \
    -e USERNAME=admin \
    -e PASSWORD=mysecret \
    apnar/rsync-server
```

```
$ rsync rsync://admin@localhost:9999
data            /data directory
```


##### Modify the default volume location

```
$ docker run \
    -p 9999:873 \
    -v /your/folder:/myvolume \
    -e USERNAME=admin \
    -e PASSWORD=mysecret \
    -e VOLUME_PATH=/myvolume \
    data/rsync-server
```

```
$ rsync rsync://admin@localhost:9999
data            /myvolume directory
```

##### Allow additional client IPs

```
$ docker run \
    -p 9999:873 \
    -v /your/folder:/myvolume \
    -e USERNAME=admin \
    -e PASSWORD=mysecret \
    -e VOLUME_PATH=/myvolume \
    -e HOSTS_ALLOW=192.168.8.0/24 192.168.24.0/24 172.16.0.0/12 127.0.0.1/32 \
    apnar/rsync-server
```


##### Over SSH

If you would like to connect over ssh, you may mount your public key or
`authorized_keys` file to `/root/.ssh/authorized_keys`.

Without setting up an `authorized_keys` file, you will be propted for the
password (which was specified in the `PASSWORD` variable).

```
docker run \
    -v /your/folder:/myvolume \
    -e USERNAME=admin \
    -e PASSWORD=mysecret \
    -e VOLUME_PATH=/myvolume \
    -e HOSTS_ALLOW=192.168.8.0/24 192.168.24.0/24 172.16.0.0/12 127.0.0.1/32 \
    -v /my/authorized_keys:/root/.ssh/authorized_keys \
    -p 9000:22 \
    apnar/rsync-server
```

```
$ rsync -av -e "ssh -i /your/private.key -p 9000 -l root" /your/folder/ localhost:/data
```

### Verify that it works

Add `test` file on server:

    $ docker exec -it rsync_server sh
      $ touch /data/test

Bring the `file` on client:

    $ docker exec -it rsync_client sh
      $ rsync -e 'ssh -p 2222' -avz root@foo.bar.com:/data/ /data/
      $ ls -l /data/

# Simple rsync container based on alpine

A simple rsync server/client Docker image to easily rsync data within Docker volumes

## Simple Usage

Get files from remote server within a `docker volume`:

    $ docker run --rm -v blobstorage:/data/ eeacms/rsync \
             rsync -avzx --numeric-ids user@remote.server.domain.or.ip:/var/local/blobs/ /data/

Get files from `remote server` to a `data container`:

    $ docker run -d --name data -v /data busybox
    $ docker run --rm --volumes-from=data eeacms/rsync \
             rsync -avz user@remote.server.domain.or.ip:/var/local/blobs/ /data/

## Advanced Usage

### Client setup

Start client to pack and sync every night:

    $ docker run --name=rsync_client -v client_vol_to_sync:/data \
                 -e CRON_TASK_1="0 1 * * * /data/pack-db.sh" \
                 -e CRON_TASK_2="0 3 * * * rsync -e 'ssh -p 2222' -aqx --numeric-ids root@foo.bar.com:/data/ /data/" \
             eeacms/rsync client

Copy the client SSH public key printed found in console

      
### Rsync data between containers in Rancher

0. Request TCP access to port 2222 to an accessible server of environment of the new installation from the source container host server.

1. Start **rsync client** on host from where do you want to migrate data (ex. production). 

    Infrastructures -> Hosts ->  Add Container
    * Select image: eeacms/rsync
    * Command: sh
    * Volumes -> Volumes from: Select source container

2. Open logs from container, copy the ssh key from the message

2. Start **rsync server** on host from where do you want to migrate data (ex. devel). The destination container should be temporarily moved to an accessible server ( if it's not on one ) .

    Infrastructures -> Hosts ->  Add Container
    * Select image: eeacms/rsync
    * Port map -> +(add) : 2222:22
    * Command: server
    * Add environment variable: SSH_AUTH_KEY="<SSH-KEY-FROM-R-CLIENT-ABOVE>"
    * Volumes -> Volumes from: Select destination container


3. Within **rsync client** container from step 1 run:

  ```
    $ rsync -e 'ssh -p 2222' -avz <SOURCE_DUMP_LOCATION> root@<TARGET_HOST_IP_ON_DEVEL>:<DESTINATION_LOCATION>
  ```
  
4. The rsync servers can be deleted, and the destination container can be moved back ( if needed )
