# Setting up Flocker on GCE using Ansible.

This tutorial will overview setting up a Flocker cluster on Google Compute
Engine. This is a new feature with Flocker 1.11.

In order to complete this tutorial, you will need a few things:

* A [Google Cloud Platform project](https://console.cloud.google.com/project)
  with billing enabled (so you can use GCE). This should also work if you are
  inside your 60 day free trial.
* The [gcloud](https://cloud.google.com/sdk/downloads) command line tool
  installed.
* Python 2.7 and virtualenv installed (`pip install virtualenv`).
* [`flockerctl`](https://docs.clusterhq.com/en/latest/flocker-features/flockerctl.html)
  to interact with your cluster.

The new GCE driver supports authentication by service accounts, including the
default service account that is implicit to the VM. This means you don't have
to ship your GCE credentials around to every node in your cluster, but you do
have to give the VM permission to make API calls to Google Compute Engine.
These credentials allow any process on the VM execute authenticated Google
Compute Engine API calls. We will demonstrate how to do this as part of this
tutorial.


1. Set up a virtualenv in a clone of this repository so you don't pollute your
   global python packages:

  ```bash
  cd <demo-root-directory>
  git clone https://github.com/ClusterHQ/gce-ansible-demo.git
  cd gce-ansible-demo
  virtualenv ./virtual-env
  source ./virtual-env/bin/activate
  ```

2. Authenticate with Google so we can spin up VMs from the command line:

  ```bash
  gcloud auth login
  ```

3. Set up some environment variables for ease of use later:

  ```bash
  # The name of the GCP project in which to bring up the instances.
  export PROJECT=<gcp-project-for-instances>

  # The name of the zone in which to bring up the instances.
  export ZONE=<gcp-zone-for-instances>

  # A tag to add to the names of each of the instances.
  # Must be all lowercase letters or dashes.
  # This is used so you can identify the instances used in this tutorial.
  export TAG=<my-gce-test-string>

  # The number of nodes to put in the cluster you are bringing up.
  export CLUSTER_SIZE=<number-of-nodes>

  # Double check all environment variables are set correctly:
  for instance in $(seq -f instance-${TAG}-%g 1 $CLUSTER_SIZE)
  do echo "Will create:  $PROJECT/$ZONE/$instance"
  done
  ```

4. Create the instances:

  ```bash
  # Set up a firewall rule that allows all tcp incoming traffic for instances
  # with the 'incoming-traffic-permitted' tag.
  gcloud compute firewall-rules create \
    allow-all-incoming-traffic \
    --allow tcp \
    --target-tags incoming-traffic-permitted \
    --project $PROJECT

  # Launch the instances
  gcloud compute instances create \
    $(seq -f instance-${TAG}-%g 1 $CLUSTER_SIZE) \
    --image ubuntu-14-04 \
    --project $PROJECT \
    --zone $ZONE \
    --machine-type n1-standard-1 \
    --tags incoming-traffic-permitted \
    --scopes https://www.googleapis.com/auth/compute
  ```

  Note that the `--scopes compute` part of this command line is the part that
  gives the VM permission to execute read/write API calls against GCE. This is
  what gives the VM, and thus the agent nodes, permission to create and attach
  disks to the VM.

5. Enable ssh to each of the VMs from the command line:

  ```bash
  gcloud compute config-ssh --project $PROJECT
  ```

  Note that this enable ssh to all of the VMs in the project from the command
  line.

6. Install flocker on your cluster.

  There are many ways to install flocker on a cluster of nodes, for
  the sake of this tutorial we are using Cluster HQ's Ansible Galaxy
  role. If you already use Ansible Galaxy, this provides a nice way to
  install flocker in your existing system.  If you are not interested
  in using the Ansible role to install flocker, you can read [our
  installation docs](https://docs.clusterhq.com/en/latest/index.html)
  on how to install flocker and skip down to step 9. The Ansible
  galaxy role simply automates some of the steps.

  Install the requirements to set up a flocker cluster using Ansible.
  This involves pip installing `flocker-ca` and `ansible-galaxy`, as well as
  getting the roles from Ansible galaxy to install docker and flocker on the
  nodes.

  * [marvinpinto.docker](https://galaxy.ansible.com/marvinpinto/docker/)
  * [ClusterHQ.flocker](https://galaxy.ansible.com/ClusterHQ/flocker/)

  TODO: Update Flocker pip install instructions to 1.11! Maybe refer to our
  documentation link.

  ```bash
  pip install ansible
  pip install https://clusterhq-archive.s3.amazonaws.com/python/Flocker-1.10.2-py2-none-any.whl
  ansible-galaxy install marvinpinto.docker -p ./roles
  ansible-galaxy install ClusterHQ.flocker -p ./roles
  ```

7. Create an inventory and an agent.yml.

  The following command lists out the instances we just constructed, and then
  pipes the output into a small python script that creates an Ansible inventory
  and an agent.yml file that are used to configure the cluster:

  ```bash
  gcloud compute instances list \
    $(seq -f instance-${TAG}-%g 1 $CLUSTER_SIZE) \
    --project $PROJECT  --zone $ZONE --format=json | \
    python create_inventory.py

  # Inspect the results of those commands:
  cat ansible_inventory
  cat agent.yml

  # Note the control node's IP address and save that in environment variable.
  export CONTROL_NODE=<control-node-ip-from-agent-yml>
  ```

8. Execute the provided Ansible playbook, which will install docker and flocker
   on all of the nodes, setting up the first node to be the flocker control
   agent.

  ```bash
  ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook \
    --key-file ~/.ssh/google_compute_engine \
    -i ./ansible_inventory \
    ./gce-flocker-installer.yml  \
    --extra-vars "flocker_agent_yml_path=${PWD}/agent.yml"
  ```

9. Once that command finishes you should have a cluster up and running. Use
   `flockerctl` to explore your cluster:

  ```bash
  flockerctl --user api_user \
    --control-service $CONTROL_NODE \
    --certs-path ${PWD}/certs \
    list-nodes
  ```

  At this point you should be able to use the certificates in ./certs to
  interact with your cluster

999. List any volumes you've created and delete them:

  ```bash
  flockerctl --user api_user \
    --control-service $CONTROL_NODE \
    --certs-path ${PWD}/certs \
    ls

  flockerctl --user api_user \
    --control-service $CONTROL_NODE \
    --certs-path ${PWD}/certs \
    destroy -d <dataset-id-1>

  flockerctl --user api_user \
    --control-service $CONTROL_NODE \
    --certs-path ${PWD}/certs \
    destroy -d <dataset-id-2>

  # Poll using ls until they are all deleted:
  flockerctl --user api_user \
    --control-service $CONTROL_NODE \
    --certs-path ${PWD}/certs \
    ls
  ```

999. At this point, it's time to shut down the cluster. Remove the convenient ssh aliases from ~/.ssh/config, they will get stale.

  ```bash
  gcloud compute config-ssh --project $PROJECT --remove
  ```

999. Delete the nodes.

  ```bash
  gcloud compute instances delete \
    $(seq -f instance-${TAG}-%g 1 $CLUSTER_SIZE) \
    --project $PROJECT \
    --zone $ZONE
  ```
