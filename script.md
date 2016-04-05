
# Script for demo:

```bash

# Set up our demo repo:

cd ~/demo
git clone https://github.com/ClusterHQ/gce-ansible-demo.git
cd gce-ansible-demo
virtualenv ./virtual-env
source ./virtual-env/bin/activate


# Authenticate with GCE:
gcloud auth login

# Setup Environment:

export PROJECT=clusterhq-acceptance
export ZONE=us-central1-c
export TAG=gce-demo-take-1
export CLUSTER_SIZE=15

for instance in $(seq -f instance-${TAG}-%g 1 $CLUSTER_SIZE)
do echo "Will create:  $PROJECT/$ZONE/$instance"
done


# Create a firewall rule:

gcloud compute firewall-rules create \
  allow-all-incoming-traffic \
  --allow tcp \
  --target-tags incoming-traffic-permitted \
  --project $PROJECT

# Create the instances:

gcloud compute instances create \
  $(seq -f instance-${TAG}-%g 1 $CLUSTER_SIZE) \
  --image ubuntu-14-04 \
  --project $PROJECT \
  --zone $ZONE \
  --machine-type n1-standard-1 \
  --tags incoming-traffic-permitted \
  --scopes https://www.googleapis.com/auth/compute

# Setup SSH:

gcloud compute config-ssh --project $PROJECT

# Install ansible, roles, and flocker-ca:

pip install ansible
pip install https://clusterhq-archive.s3.amazonaws.com/python/Flocker-1.10.2-py2-none-any.whl
ansible-galaxy install marvinpinto.docker -p ./roles
ansible-galaxy install ClusterHQ.flocker -p ./roles

# Create ansible inventory and agent.yml.

gcloud compute instances list \
  $(seq -f instance-${TAG}-%g 1 $CLUSTER_SIZE) \
  --project $PROJECT  --zone $ZONE

cat create_inventory.py

ls

gcloud compute instances list \
  $(seq -f instance-${TAG}-%g 1 $CLUSTER_SIZE) \
  --project $PROJECT  --zone $ZONE --format=json | \
  python create_inventory.py

ls

cat ansible_inventory

cat agent.yml

export CONTROL_NODE=???

# Install flocker using ansible:

ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook \
  --key-file ~/.ssh/google_compute_engine \
  -i ./ansible_inventory \
  ./gce-flocker-installer.yml  \
  --extra-vars "flocker_agent_yml_path=${PWD}/agent.yml"

# You should have a cluster up and ready:

flockerctl --user api_user \
  --control-service $CONTROL_NODE \
  --certs-path ${PWD}/certs \
  list-nodes

flockerctl --user api_user \
  --control-service $CONTROL_NODE \
  --certs-path ${PWD}/certs \
  status

flockerctl --user api_user \
  --control-service $CONTROL_NODE \
  --certs-path ${PWD}/certs \
  create -n ???

flockerctl --user api_user \
  --control-service $CONTROL_NODE \
  --certs-path ${PWD}/certs \
  ls

flockerctl --user api_user \
  --control-service $CONTROL_NODE \
  --certs-path ${PWD}/certs \
  destroy -d ???

flockerctl --user api_user \
  --control-service $CONTROL_NODE \
  --certs-path ${PWD}/certs \
  ls

# Remove ssh aliases

gcloud compute config-ssh --project $PROJECT --remove

# Delete the nodes.

gcloud compute instances delete \
  $(seq -f instance-${TAG}-%g 1 $CLUSTER_SIZE) \
  --project $PROJECT \
  --zone $ZONE

```

