#!/bin/bash

source /vagrant/vagrant/bootstrap-ssh.sh

cat /vagrant/vagrant/id_rsa.pub >> ~/.ssh/authorized_keys
cat /vagrant/vagrant/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys
chown vagrant /home/vagrant/.ssh/authorized_keys

echo "Creating bare server repo..."
rm -rf /tmp/server && \
	cp -r /vagrant/test/fixtures/server /tmp && \
	mv /tmp/server/_git /tmp/server/.git && \
	mkdir -p /repo && \
	rm -rf /repo/server && \
	cd /repo && \
	git clone --bare /tmp/server ./server > /dev/null && \
	echo "Making the bare repo writeable..." && \
	chmod -R a+w /repo/server

