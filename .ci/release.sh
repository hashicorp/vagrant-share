#!/usr/bin/env bash
# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0


csource="${BASH_SOURCE[0]}"
while [ -h "$csource" ] ; do csource="$(readlink "$csource")"; done
root="$( cd -P "$( dirname "$csource" )/../" && pwd )"

. "${root}/.ci/load-ci.sh"

wrap_raw pushd "${root}"

# Read the version we are building
version="$(<./version.txt)"

# Publish the new gem
publish_to_rubygems

slack -m "New version of vagrant-share published: v${version}"
