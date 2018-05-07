# Docker Swarm-Ready Salt-Master with API and Molten UI

A Docker image running a containerised Salt-Master server with Salt-API and [Molten UI](https://github.com/martinhoefling/molten) with an optional [Multi-Master-PKI](http://docs.saltstack.com/en/latest/topics/tutorials/multimaster_pki.html) setup.

## Prerequisites

[Docker](https://www.docker.com/) must be installed.

## Running the Container

You can easily run the container like so:

    docker run --rm -it --name salt-master --publish 4505:4505 --publish 4506:4506 --publish 443:443 mgolly/salt-master

or in docker swarm:

    docker service create --publish 4505:4505 --publish 4506:4506 --publish 443:443 mgolly/salt-master

## Running Salt Commands

Use `docker exec` to enter the salt-master container and execute salt commands.

Once installed run:

    $ CONTAINER_ID=$(docker run -d --name salt-master --publish 4505:4505 --publish 4506:4506 --publish 443:443 mgolly/salt-master)
    $ docker exec -it $CONTAINER_ID /bin/sh
    $ root@CONTAINER_ID:~# salt '*' test.ping
    $ root@CONTAINER_ID:~# salt '*' grains.items


## Ports

The following exposed ports allow minions to communicate with the Salt Master:
 * `4505`
 * `4506`

The following exposed port allows access to Salt-API and the Molten UI:
 * `443`


## Environment Variables

This container recognizes the following environment variables.  They can be set to the values desired, or optionally in "swarm" mode (i.e. container executed with `docker service`), they can be set to the name of a docker secret that contains the value desired.

### Logging Level
 * `LOG_LEVEL`: The level to log at, defaults to `error`

### Master Key
 * `MASTER_PEM`: Salt Master private key, defaults to autogenerated on first run.
 * `MASTER_PUB`: Salt Master public key, defaults to autogenerated on first run.

### Pre-shared Minion Keys
 * `MINIONS`: List of minions to pre-accept keys for, space delimited, default blank.  Requires MASTER_* keys to be set.
 * `${minion}_KEY`: Key of a minion for pre-acceptance.  Requires MASTER_* keys to be set.

### User Accounts for Salt-API / Molten UI
 * `ACCOUNTS`: List of user or group accounts for access to salt-api and molten, space delimited, default blank.
 * `${account}_PASSWORD`: Password for a user account.  If set, `${account_LIST}` should not be set.
 * `${account}_LIST`: List of user accounts in this group, space delimited, default blank.  If set, `${account_PASSWORD}` should not be set.
 * `${account}_ACCESS`: Salt-API / Molten account settings.  Contents should only be the final settings below the username in [SaltStack eauth](https://docs.saltstack.com/en/latest/topics/eauth/) settings and be left-justified (no spaces) unless YAML-indented.  It should look something like:
```
- .*
- '@runner'
- '@wheel'
- '@jobs'
```

### Cert Generation for Salt-API / Molten UI
 * `API_CERT_INDEX`: Salt-API certificate index.  Will be auto-generated if left undefined or blank.
 * `API_CERT_CRT`: Salt-API certificate.  Will be auto-generated if left undefined or blank.
 * `API_CERT_KEY`: Salt-API certificate key.  Will be auto-generated if left undefined or blank.

### Extra [Salt Master Config](https://docs.saltstack.com/en/latest/ref/configuration/master.html)
 * `CONFIGS`: List of other config to insert into master's configuration (/etc/salt/master.d), space delimited, default blank.  (Can use docker swarm secrets or configs.)
 * `${config}_CONFIG`: Config to insert into master's configuration (i.e. /etc/salt/master.d/).  (Can use docker swarm secrets or configs.)

## Volumes

The following volumes can be [mounted](https://docs.docker.com/userguide/dockervolumes/):

 * `/etc/salt/master.d` - Master configuration include directory
 * `/etc/salt/pki` - This holds the Salt Minion authentication keys and the Salt API / Molten UI TLS certificate
 * `/srv/salt` - Holds your states, pillars, etc
 * `/var/cache/salt` - Job and Minion data cache
 * `/var/logs/salt` - Salts log directory

Note that mounting a volume on `/etc/salt/pki/` could provide easier access to the `master.pem` key.  This is a security risk and should be properly mitigated in secure environments.

## License

This project uses the Apache License 2.0.  See the [LICENSE](LICENSE) file for details.

## Acknowledgments

 * [SaltStack](https://saltstack.org/) for a great piece of software!
 * [digitalr00ts](https://github.com/digitalr00ts/) for:
   * the alpine base image,
   * [tini](https://github.com/krallin/tini) integration,
   * TLS for the API (with autogenerating self-signed certs), and
   * salt-master and API healthcheck.
 * [dkiser](https://github.com/dkiser/) for:
   * list of volumes for a salt-master container, and
   * the [multi-master PKI](http://docs.saltstack.com/en/latest/topics/tutorials/multimaster_pki.html) setup.
 * [bbinet](https://github.com/bbinet/) for:
   * how to integrate Molten UI into a salt-master docker container, and
   * pre-creating users and master keys.
