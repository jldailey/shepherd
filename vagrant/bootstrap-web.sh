#!/bin/bash

bash /vagrant/vagrant/bootstrap-ssh.sh

echo "Cleaning out old code..."
killall node 2> /dev/null
rm -rf /opt/server
cd /opt && \
	echo "git clone..." && \
	git clone git+ssh://vagrant@10.10.10.5/repo/server && \
	echo "npm install..." && \
	cd server && \
	npm install 2> /dev/null && \
	echo "npm link..." && \
	npm link /vagrant 2> /dev/null && \
	echo "link nginx config..." && \
	ln -sf /opt/server/node_modules/shepherd/conf/nginx.conf /etc/nginx/conf.d/shepherd.conf && \
	echo "launch shepherd daemon..." && \
	./node_modules/.bin/shepherd --daemon -f /vagrant/vagrant/shepherd.json -o /var/log/shepherd.log -p /var/run/shepherd.pid

