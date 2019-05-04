# nodejs.sh

This script is a transparent wrapper to run your node projects in per project docker containers. It provides an additional security layer as you can run eg each client's projects in a separate container so you are guaranteed eg a misbehaving npm dependency has restricted access and is contained to a single project

## Install

> bash v4.3+ is required, which means on CentOS 7 you have to install bash from source

Make sure you have a working docker daemon installed on your system

```
wget https://raw.githubusercontent.com/pimlie/nodejs.sh/master/nodejs.sh
chmod +x nodejs.sh
sudo mv nodejs.sh /usr/local/sbin
ln -s nodejs.sh /usr/local/sbin/node
ln -s nodejs.sh /usr/local/sbin/npm
ln -s nodejs.sh /usr/local/sbin/yarn
```
> As eg `npm-check-updates` add symlinks to `/usr/local/bin`, we recommend to add symlinks to `/usr/local/sbin` as on Ubuntu/CentOS this has a higher priority and you can still access your local node install

## How it works

This scripts pulls official node docker containers based on the version requested. It then assigns each container a unique name based on the version and the specified id.

When you execute a node command the command is passed to a `docker exec` on the container. This means the docker container needs to have a volume which is bound to your project folder

## Options

These options can be set on the cli, as environment variable or in a `.noderc` config file (see below)

- `--node-version` / `NODE_VERSION`

Which node version you want to run. This version should be available as container from the official node docker repository: https://hub.docker.com/_/node

Eg: _--node-version 11.15.0_

- `--node-id` / `NODE_ID`

An identifier for your project or projects dir

Eg: _--node-id clientX_

- `--node-remove`

When supplied an existing docker container is removed so a new one is created

- `--copy-env`

A regular expression of environment variable names you want to copy to the docker container. These are only copied once and are not persistent in the docker container

Eg: _--copy-env "^(HOST|PORT|CI_.*)$"_

> Any environment variable starting with `NODE_` will always be copied to the container

## Configure

### Global configuration

The global configuration is stored in: `/etc/nodejs-sh.conf`

- `defaultNodeId`

The default id which is used. This is helpful if you dont want to include any volumes by default

- `volumes`

An array of all paths which should be added as a volume to _all_ containers

- `volumes_${nodeId}`

An array of all paths which should be added as a volume to containers for _${nodeId}_

Example config:
```
# /etc/nodejs-sh.conf
defaultNodeId=opensource

volumes=("/var/projects/libraries")

volumes_opensource=("/var/projects/github")

volumes_clientX=(
  "/var/projects/clientX_project1"
  "/var/projects/clientX_project2"
)
```

### Project (dir) configuration

You can create a `.noderc` file to control per project options. See [Options](#Options) for the possible list of options

Example configs

```
# /var/projects/clientX/.noderc
NODE_ID=clientX
NODE_VERSION=10
COPY_ENV="^(CI_.*)$"
```

```
# /var/projects/github/.noderc
NODE_ID=opensource
NODE_VERSION=12
COPY_ENV="^(HOST|PORT)$"
```

With the above examples then when running `node` will result in using node version 12 for your opensource projects and node version 10 for clientX projects.

> The first `.noderc` file which is found in your parent folder tree is used. Eg given a file `/var/projects/clientX/.noderc` then running node in the folder `/var/projects/clientX/projectY` will also use the `.noderc` file in `clientX` unless you `projectY` contains a ``.noderc` file as well

## Caveats

- The current working directory (`pwd`) is also used as working directory in the docker container. If your `pwd` is not available in the docker container then executing `node` will result in an error
- npm / yarn caches are not shared between containers
- commands are run in the container as the user node which has a user id of `1000`
- bash v4.3+ is required (which is eg not available for install by default on Cent OS v7)
