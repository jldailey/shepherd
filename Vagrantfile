# -*- mode: ruby -*-
# vim: set ft=ruby:

Vagrant.configure("2") do |config|

	# the web server
	config.vm.define "web" do |web|
		web.vm.box = "jldailey/debian-node-base"
		web.vm.provision :shell, :path => "vagrant/bootstrap-web.sh"
		web.vm.network "private_network", ip: "10.10.10.6"
		web.vm.network "forwarded_port", guest: 8000, host: 8000 # nginx should be on 8000 doing a reverse proxy to a shepherd pool on 8001-8004
		web.vm.network "forwarded_port", guest: 9000, host: 9000 # shepherd http server
		web.vm.provider "virtualbox" do |vb|
			 vb.customize ["modifyvm", :id, "--cpus", "4"]
		end
	end

	config.vm.define "git" do |git|
		git.vm.box = "jldailey/debian-node-base"
		git.vm.provision :shell, :path => "vagrant/bootstrap-git.sh"
		git.vm.network "private_network", ip: "10.10.10.5"
	end

	config.vm.define "rabbit" do |rabbit|
		rabbit.vm.box = "jldailey/debian-node-base"
		rabbit.vm.provision :shell, :inline => "apt-get update && apt-get -y install rabbitmq-server"
		rabbit.vm.network "forwarded_port", guest: 5672, host: 5672
		rabbit.vm.network "private_network", ip: "10.10.10.3"
	end

end
