# Vagrant Share

Vagrant Share allows you to share your Vagrant environment with
anyone in the world, enabling collaboration directly in your
Vagrant environment in almost any network environment with a
single command.

Documentation: https://www.vagrantup.com/docs/share

## Usage

First, install the plugin:

```
$ vagrant plugin install vagrant-share
```

By default, `vagrant share` will share the guest's HTTP server
using the forwarded port on the host attached to port 80 on the
guest.

For example, given the following Vagrantfile:

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "hashicorp/bionic64"
  config.vm.provision :shell, inline: "DEBIAN_FRONTEND=noninteractive apt-get install -yq apache2"
  config.vm.network :forwarded_port, guest: 80, host: 9999
end
```

Once the guest has been started and provisioned, the web server
can be made publicly available by running:

```
$ vagrant share
```

### SSH

Vagrant Share can also allow sharing of the SSH connection to
a local guest. This can be initiated by starting the share session
with the SSH option:

```
$ vagrant share --ssh --ssh-no-password --disable-http
```

Once the share session has been started, a random name for the
session will be output. Provide that name to another user, and
they can connect using that name:

```
$ vagrant connect --ssh RANDOM_NAME
```

### Full Share

Vagrant Share can also provide full access to the local guest. This
can be done using the full option:

```
$ vagrant share --full --disable-http
```

Once the share session has been started, a random name for the
session will be output. Provide that name to another user, and
they can connect using that name:

```
$ vagrant connect RANDOM_NAME
```

A local static IP will be provided which can be used to access
the remote guest.

## Requirements

Vagrant Share currently uses [ngrok](https://ngrok.com/) for
providing the underlying connection.

## Development & Contributing

Pull requests are very welcome!

Install dependencies:
```
bundle install
```

Run the tests:
```
bundle exec rake
```
