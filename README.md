# nodejs.sh

This script is a transparent wrapper to run your node projects in per project docker containers. It provides an additional security layer as you can run eg each client's projects in a separate container so you are guaranteed eg a misbehaving npm dependency has restricted access and is contained to a single project

## Install

> Bash v4.3+ is required

Make sure you have a working docker daemon installed on your system and your user has been added to the `docker` group

```
wget https://raw.githubusercontent.com/pimlie/nodejs.sh/master/nodejs.sh
chmod +x nodejs.sh
sudo mv nodejs.sh /usr/local/sbin
```

Then create symlinks to the node commands. You could choose not to link them all, eg if you use yarn and always run a script from your package.json you only need to link `yarn` and you can leave node to point to your local install

> If you choose not to symlink `node` or dont have node installed locally as well, please also symlink globally installed commands like `ncu`, `vue` etc

```
sudo ln -s nodejs.sh /usr/local/sbin/node
sudo ln -s nodejs.sh /usr/local/sbin/npm
sudo ln -s nodejs.sh /usr/local/sbin/yarn
```

After this you probably need to sign out and in for your shell to pickup the new paths

> As eg running `n` add symlinks to `/usr/local/bin`, we recommend to add symlinks to `/usr/local/sbin` as on Ubuntu/CentOS this has a higher priority and you can still access your local node install

## How it works

This scripts pulls official node docker containers based on the version requested. It then creates a container for that image with a unique name based on the version and the specified (project) id.

When you execute a node command the command is passed to a `docker exec` on the container. This means the docker container needs to have a volume which is bound to your project folder

## Options

These options can be set on the cli, as environment variable or in a `.noderc` config file (see below)

- `--node-id` / `NODE_ID`

An identifier for your project or projects dir

Eg: _--node-id clientX_

- `--node-version` / `NODE_VERSION`

Which node version you want to run. This version should be available as container from the official node docker repository: https://hub.docker.com/_/node

Eg: _--node-version 11.15.0_

- `--node-user` / `NODE_USER`

As which user the command should be run in the docker container, uses the docker exec option `--user`

Eg: _--node-user node_

> By default global commands (specified by `-g` or `--global`) are run as user _root_, all other commands are run as user _node_ with id _1000_

- `--node-remove`

When supplied the existing docker container is removed and a new one is created

- `--copy-env` / `COPY_ENV`

A comma separated list or regular expression of environment variable names you want to copy to the docker container. These are only copied once and are not persistent in the docker container

Eg: _--copy-env "^(HOST|PORT|CI_.*)$"_ or _--copy-env "HOST,PORT"_

> Any environment variable starting with `NODE_` will always be copied to the container

## Configure

### Global configuration

The global configuration is stored in: `/etc/nodejs-sh.conf`

- `rcFile` (default: _.noderc_)

The name of the rc file with project configuration to look for

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
- global packages are only installed for the current `node_id`, if you need to have the global package in all containers you should run the install command for all containers
- Bash v4.3+ is required (which is eg not available for install by default on Cent OS v7)

Here is a bash install from source oneliner :)
```
wget http://ftp.gnu.org/gnu/bash/bash-4.4.18.tar.gz && tar xzf ./bash-4.4.18.tar.gz -C /tmp && cd /tmp/bash-4.4.18 && ./configure && make && make install && cd - && rm -Rf /tmp/bash-4.4.18 && rm bash-4.4.18.tar.gz
```

## Overhead

Using this wrapper has a small (but imo neglible) overhead ofc, see below for some numbers

- Local install
```
$ time node -v
v12.0.0

real	0m0.002s
user	0m0.002s
sys	0m0.000s
```

- docker exec directly
```
$ time docker exec node node -v
v12.0.0

real	0m0.152s
user	0m0.020s
sys	0m0.013s
```

- nodejs.sh
```
$ time node -v
v12.0.0

real	0m0.246s
user	0m0.058s
sys	0m0.055s
```
