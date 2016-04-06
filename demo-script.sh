#!/usr/bin/env bash

set -eu

# ************************************************************
# Setup demo magic:
# ************************************************************

DEMO_MAGIC=https://raw.githubusercontent.com/paxtonhare/demo-magic/master/demo-magic.sh

DEMO_MAGIC_FILE=demo-magic.sh

if [[ ! -e ${DEMO_MAGIC_FILE} ]]
then
  curl -sSL ${DEMO_MAGIC} > ${DEMO_MAGIC_FILE}
fi

source ${DEMO_MAGIC_FILE}

TYPE_SPEED=15
DEMO_PROMPT="${GREEN}➜ ${BLUE}\W${BROWN}$ "

clear

# ************************************************************
# Run the demo:
# ************************************************************

cd
p "# Set up our demo repo:"
pe "cd ~/demos"
pe "git clone https://github.com/ClusterHQ/gce-ansible-demo.git"
pe "cd gce-ansible-demo"
pe "virtualenv ./virtual-env"

# I don't trust demo magic for sourcing bash scripts:
p "source ./virtual-env/bin/activate"

set +u
source ./virtual-env/bin/activate
set -u


p "# Authenticate with GCE:"
p "gcloud auth login"


p "# Setup Environment:"

p "export PROJECT=clusterhq-acceptance"
export PROJECT=clusterhq-acceptance

p "export ZONE=us-central1-c"
export ZONE=us-central1-c

p "export TAG=gce-demo-take-2"
export TAG=gce-demo-take-2

export CLUSTER_SIZE=4
p "export CLUSTER_SIZE=${CLUSTER_SIZE}"

pe 'for instance in $(seq -f instance-${TAG}-%g 1 $CLUSTER_SIZE)
    do echo "Will create:  $PROJECT/$ZONE/$instance"
    done'

p "# Create a firewall rule:"
pe 'gcloud compute firewall-rules create \
  allow-all-incoming-traffic \
  --allow tcp \
  --target-tags incoming-traffic-permitted \
  --project $PROJECT'

p '# Create the instances:'
p '# Note the use of --scopes to give the VM permission to make GCE API'
p '# requests in this project.'
pe 'gcloud compute instances create \
  $(seq -f instance-${TAG}-%g 1 $CLUSTER_SIZE) \
  --image ubuntu-14-04 \
  --project $PROJECT \
  --zone $ZONE \
  --machine-type n1-standard-1 \
  --tags incoming-traffic-permitted \
  --scopes https://www.googleapis.com/auth/compute'

p "# Setup SSH:"

pe 'gcloud compute config-ssh --project $PROJECT'

p '# Install ansible, roles, and flocker-ca:'

pe 'pip install ansible'
pe 'pip install https://clusterhq-archive.s3.amazonaws.com/python/Flocker-1.11.0-py2-none-any.whl'
pe 'ansible-galaxy install marvinpinto.docker -p ./roles'
pe 'ansible-galaxy install ClusterHQ.flocker -p ./roles'

p '# Create ansible inventory and agent.yml.'

pe 'gcloud compute instances list \
  $(seq -f instance-${TAG}-%g 1 $CLUSTER_SIZE) \
  --project $PROJECT  --zone $ZONE'

p '# Use a python script to create an ansible role and agent.yml from the '
p '# list of instances'
pe 'head create_inventory.py'
pe 'echo ...'
pe 'tail create_inventory.py'

pe 'ls'

pe 'gcloud compute instances list \
  $(seq -f instance-${TAG}-%g 1 $CLUSTER_SIZE) \
  --project $PROJECT  --zone $ZONE --format=json | \
  python create_inventory.py'

pe 'ls'

p '# Look at the new files:'
pe 'cat ansible_inventory'
pe 'cat agent.yml'

export CONTROL_NODE=`cat agent.yml | grep 'hostname:' | sed 's/^.*hostname: //'`

p "export CONTROL_NODE=${CONTROL_NODE}"

p "# Install flocker using ansible using the playbook in this repo:"

pe 'cat ./gce-flocker-installer.yml'

pe 'ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook \
  --key-file ~/.ssh/google_compute_engine \
  -i ./ansible_inventory \
  ./gce-flocker-installer.yml  \
  --extra-vars "flocker_agent_yml_path=${PWD}/agent.yml"'

p '# You should have a cluster up and ready:'

pe 'flockerctl --user api_user \
  --control-service $CONTROL_NODE \
  --certs-path ${PWD}/certs \
  list-nodes'

NODE=$(flockerctl --user api_user \
  --control-service $CONTROL_NODE \
  --certs-path ${PWD}/certs \
  list-nodes | awk 'NR==3 {print $1}')

pe "flockerctl --user api_user \\
  --control-service \$CONTROL_NODE \\
  --certs-path \${PWD}/certs \\
  create -n $NODE"

pe 'flockerctl --user api_user \
  --control-service $CONTROL_NODE \
  --certs-path ${PWD}/certs \
  ls'

pe 'flockerctl --user api_user \
  --control-service $CONTROL_NODE \
  --certs-path ${PWD}/certs \
  ls'

pe 'flockerctl --user api_user \
  --control-service $CONTROL_NODE \
  --certs-path ${PWD}/certs \
  ls'

DATASET=$(flockerctl --user api_user \
  --control-service $CONTROL_NODE \
  --certs-path ${PWD}/certs \
  ls | grep 'attached' | awk '{print $1}')

pe "flockerctl --user api_user \\
  --control-service \$CONTROL_NODE \\
  --certs-path \${PWD}/certs \\
  destroy -d $DATASET"

pe 'flockerctl --user api_user \
  --control-service $CONTROL_NODE \
  --certs-path ${PWD}/certs \
  ls'

pe 'flockerctl --user api_user \
  --control-service $CONTROL_NODE \
  --certs-path ${PWD}/certs \
  ls'

pe 'flockerctl --user api_user \
  --control-service $CONTROL_NODE \
  --certs-path ${PWD}/certs \
  ls'

########################################
# Cleanup
########################################

p '# Remove ssh aliases'

pe 'gcloud compute config-ssh --project $PROJECT --remove'

p '# Delete the nodes.'
pe 'gcloud compute instances delete \
  $(seq -f instance-${TAG}-%g 1 $CLUSTER_SIZE) \
  --project $PROJECT \
  --zone $ZONE'

p '# Thanks for watching!'
