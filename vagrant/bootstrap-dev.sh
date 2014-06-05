#!/bin/bash

source bootstrap-ssh.sh

echo "Cloning repo..."
mkdir -p ~/Projects
cd ~/Projects && \
	git clone git+ssh://10.10.10.5/repo/server

