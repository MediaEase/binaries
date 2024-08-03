# Vagrantfile to set up a Debian environment
Vagrant.configure("2") do |config|
  # Specify the base box
  config.vm.box = "debian/bullseye64" # Replace with the desired Debian version if needed

  # Set the VM hostname
  config.vm.hostname = "debian-vm"

  # Configure the VM provider settings
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "1024" # Set the amount of RAM
    vb.cpus = 2        # Set the number of CPUs
  end

  # Configure network settings
  config.vm.network "private_network", type: "dhcp"

  # Provisioning steps (optional)
  config.vm.provision "shell", inline: <<-SHELL
    # Update and upgrade the package list
    apt-get update -y
    apt-get upgrade -y

    # Install necessary packages
    apt-get install -y git curl wget
    wget -qO setup.sh https://raw.githubusercontent.com/MediaEase/MediaEase/develop/setup.sh && chmod +x setup.sh
  SHELL
end
