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

> If you choose not to symlink `node` or dont have node installed locally as well, please also symlink globally installed commands like [`ncu`](https://www.npmjs.com/package/npm-check-updates), [`vue`](https://www.npmjs.com/package/@vue/cli) etc

```
sudo ln -s nodejs.sh /usr/local/sbin/node
sudo ln -s nodejs.sh /usr/local/sbin/npm
sudo ln -s nodejs.sh /usr/local/sbin/yarn
```

After this you probably need to sign out and in for your shell to pickup the new paths

> As eg running [`n`](https://www.npmjs.com/package/n) add symlinks to `/usr/local/bin`, we recommend to add symlinks to `/usr/local/sbin` as on Ubuntu/CentOS this has a higher preference and you can still access your local node install

## How it works

This scripts pulls official node docker containers based on the version requested. It then creates a container for that image with a unique name based on the version and the specified (project) id.

When you execute a node command the command is passed to a `docker exec` on the container. This means the docker container needs to have a volume which is bound to your project folder

## Options

These options can be set on the cli, as environment variable or in a `.noderc` config file (see below)

- `--node-id` / `NODE_ID`

An identifier for your project or projects dir

Eg: _--node-id clientX_

- `--node-version` / `NODE_VERSION`

Which node version you want to run. This version should be available as container from the [official node docker repository](https://hub.docker.com/_/node)

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

- `imageTag` (default: _alpine_)

The image tag to use available from the [official node docker repository](https://hub.docker.com/_/node) (without the version), by default _alpine_ is used. Set to empty string to use node's default

Eg: `imageTag=` (to use node's default), `imageTag=stretch` or `imageTag=jessie-slim`

- `defaultNodeId`

The default id which is used. This is helpful if you dont want to include any volumes by default

- `dockerOptions`
- `dockerOptions_${nodeId}`

An array of additional options that should be added when creating a new node container. When specified as `dockerOptions_${nodeId}` then the options are only added to the _$nodeId_ container. See [`docker run`](https://docs.docker.com/engine/reference/commandline/run/) for available options

- `volumes`
- `volumes_${nodeId}`

An array of all paths which should be added as a volume to a container. When specified as `volumes_${nodeId}` then the volumes will only be added to the _$nodeId_ container

- `packages`
- `packages_${nodeId}`

An array of system packages that should be installed when a new container has been created. When specified as `packages_${nodeId}` then the system packages will only be installed for the _$nodeId_ container

- `npmPackages`
- `npmPackages_${nodeId}`

An array of npm packages that should be globally installed when a new node container has been created.  When specified as `npmPackages_${nodeId}` then the npm packages will only be installed for the _$nodeId_ container

- `afterCreate_${nodeId}`

A bash function that is called after the container has been created. Use this to eg set a global git username or copy npm credentials (see example below)

Example config:
```
# /etc/nodejs-sh.conf

rcFile=".noderc"

defaultNodeId="opensource"

imageTag="alpine"

volumes=("/var/projects/libraries")

volumes_opensource=("/var/projects/github")

volumes_clientX=(
  "/var/projects/clientX_project1"
  "/var/projects/clientX_project2"
)

dockerOptions=("--dns=1.1.1.1")

dockerOptions_opensource=("--dns=8.8.8.8")

# for e2e browser testing
packages_opensource=("chromium" "git")

# so we can always run ncu to update all dependencies
npmPackages=("npm-check-updates")

function afterCreate_opensource {
  containerName=$1

  # copy npm credentials to container so we can run 'npm publish'
  # (probably better to keep this outside the container though)
  local npmRc=$(cat ~/.npmrc)
  docker exec -u node "$containerName" sh -c 'echo "'"$npmRc"'" > ~/.npmrc'

  # copy git credentials so eg 'standard-version' can push to eg github
  # (probably better to keep this outside the container though
  local gitCr=$(cat ~/.git-credentials)
  docker exec -u node "$containerName" sh -c 'echo "'"$gitCr"'" > ~/.git-credentials'

  # set a global user if you dont have added one in your repository
  # (make sure to add git in packages_opensource above as well!)
  docker exec -u node "$containerName" git config --global user.name "your username"
  docker exec -u node "$containerName" git config --global user.email "your email"
}

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

> The first `.noderc` file which is found in your parent folder tree is used. Eg given a file `/var/projects/clientX/.noderc` then running node in the folder `/var/projects/clientX/projectY` will also use the `.noderc` file in `clientX` unless `projectY` contains a ``.noderc` file as well

## Caveats

- The current working directory (`pwd`) is also used as working directory in the docker container. If your `pwd` is not available in the docker container then executing `node` will result in an error
- npm / yarn caches are not shared between containers
- global packages are only installed for the current `node_id`, if you need to have the global package in all containers you should run the install command for all containers
- Bash v4.3+ is required (which is eg not available for install by default on Cent OS v7)
- There is no SIGTERM or SIGINT fired when you close the terminal of a running node command. This means that if you have eg an Express server running and close the terminal, that Express server will keep running in the docker container. So the next time you start your command eg the port will already be used.

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

real	0m0.130s
user	0m0.018s
sys	0m0.015s
```

- nodejs.sh
```
$ time node -v
v12.0.0

real	0m0.177s
user	0m0.034s
sys	0m0.049s
```
