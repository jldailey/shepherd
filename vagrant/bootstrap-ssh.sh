#!/bin/bash

echo "Configuring SSH..."
SSH_CONFIG=/etc/ssh/ssh_config
SSH_DONE=`grep "Host 10.10.10" $SSH_CONFIG`
if [ -z "$SSH_DONE" ]; then
	echo Patching SSH configuration at $SSH_CONFIG
	echo 'Host 10.10.10.*' >> $SSH_CONFIG
	echo "    StrictHostKeyChecking no" >> $SSH_CONFIG
	echo "    UserKnownHostsFile=/dev/null" >> $SSH_CONFIG
fi
cp /vagrant/vagrant/id_rsa* ~/.ssh
