# Vagrantfile: Define a lightweight Ubuntu VM and provision it with Ansible
Vagrant.configure("2") do |config|
    config.vm.box = "ubuntu/focal64"  # Ubuntu 20.04 LTS base image (lightweight server)
    config.vm.hostname = "k8s-lxc-host"
    config.vm.provider "virtualbox" do |vb|
      vb.name = "k8s-lxc-cluster-vm"
      vb.memory = 6144        # 6 GB RAM for VM (adjust as needed)
      vb.cpus = 4             # 4 CPU cores for VM
    end
  
    # Network: private network for VM (optional, for direct host access)
    # config.vm.network "private_network", ip: "192.168.56.10"
  
    # Sync the project folder to /vagrant inside VM for access to files
    config.vm.synced_folder ".", "/vagrant", type: "virtualbox"
  
    # Use Ansible (local) to provision the VM after boot
    config.vm.provision "ansible_local" do |ansible|
      ansible.playbook = "provision.yml"
      ansible.extra_vars = { host_ip: "0.0.0.0" }
      # The extra_vars host_ip isn't critical here; it's just an example of passing vars if needed
    end
  end
  