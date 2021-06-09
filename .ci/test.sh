#!/usr/bin/env bash

csource="${BASH_SOURCE[0]}"
while [ -h "$csource" ] ; do csource="$(readlink "$csource")"; done
root="$( cd -P "$( dirname "$csource" )/../" && pwd )"

pushd "${root}"

# Ensure bundler is installed
gem install --no-document bundler || exit 1

# Install the bundle
bundle install || exit 1

# Run tests
bundle exec rake || exit 1
