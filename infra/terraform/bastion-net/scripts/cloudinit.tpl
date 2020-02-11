#!/bin/bash

function log()
{
  echo "[$(date +%F_%T)] $1" >> /tmp/ado_cloud_init.log
}

log "Starting cloud_init script"

log "Creating Directory: ~/ado_config"
mkdir ~/ado_config

log "Creating ado_config.sh script local"

{
cat <<-"EOF"  > ~/ado_config/ado_config.sh
#!/bin/bash

sudo apt-get update

cd ~/ado_config

wget --output-document vsts-agent.tar.gz "https://vstsagentpackage.azureedge.net/agent/2.164.6/vsts-agent-linux-x64-2.164.6.tar.gz"

mkdir myagent && cd myagent
sudo tar zxvf ~/ado_config/vsts-agent.tar.gz

sudo chmod o+w -R ~/ado_config/myagent

sudo ./bin/installdependencies.sh

sh ./config.sh --unattended  --url "${server_url}" --auth pat --token "${pat_token}" --pool "${pool_name}" --agent $(hostname) --acceptTeeEula

sudo ./svc.sh install

sudo ./svc.sh start

sudo ./svc.sh status

sudo apt install curl
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

sudo apt install unzip -y


sudo apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-key fingerprint 0EBFCD88

sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs)  stable"

sudo apt-get install docker-ce docker-ce-cli containerd.io

sudo usermod -aG docker $USER

# Auto-start on boot
sudo systemctl enable docker

# Start right now 
sudo systemctl start docker 

sudo reboot

EOF
} 2>&1 | tee -a /tmp/ado_cloud_init.log

log "Running of cloud_init script: ~/ado_config/ado_config.sh"
log "Running as root"

cd ~/ado_config
log "Setting permissions"
sudo chmod o+x -R ./

log "Running ado_config.sh"
sh ./ado_config.sh >> /tmp/ado_config.log 2>&1 

log "End of cloud_init script"