Vagrant.configure("2") do | config |
  config.vm.box = "centos/stream9"
  config.vm.hostname = "systemd"
  config.vm.network "private_network", ip: "192.168.56.10"
  config.vm.provider "virtualbox" do |vb|
    vb.name = "systemd"
    vb.memory = 2048
    vb.cpus = 1
  end
  config.vm.provision "shell", path: "provision.sh"
end
