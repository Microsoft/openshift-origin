#!/bin/bash

echo $(date) " - Starting Script"

set -e

export SUDOUSER=$1
export PASSWORD="$2"
export PRIVATEKEY=$3
export MASTER=$4
export MASTERPUBLICIPHOSTNAME=$5
export MASTERPUBLICIPADDRESS=$6
export INFRA=$7
export NODE=$8
export NODECOUNT=$9
export INFRACOUNT=${10}
export MASTERCOUNT=${11}
export ROUTING=${12}
export REGISTRYSA=${13}
export ACCOUNTKEY="${14}"
export TENANTID=${15}
export SUBSCRIPTIONID=${16}
export AADCLIENTID=${17}
export AADCLIENTSECRET="${18}"
export RESOURCEGROUP=${19}
export LOCATION=${20}
export METRICS=${21}
export LOGGING=${22}
export COCKPIT=${23}
export AZURE=${24}
export STORAGEKIND=${25}

# Determine if Commercial Azure or Azure Government
CLOUD=$( curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/location?api-version=2017-04-02&format=text" | cut -c 1-2 )
export CLOUD=${CLOUD^^}

export MASTERLOOP=$((MASTERCOUNT - 1))
export INFRALOOP=$((INFRACOUNT - 1))
export NODELOOP=$((NODECOUNT - 1))

# Generate private keys for use by Ansible
echo $(date) " - Generating Private keys for use by Ansible for OpenShift Installation"

runuser -l $SUDOUSER -c "echo \"$PRIVATEKEY\" > ~/.ssh/id_rsa"
runuser -l $SUDOUSER -c "chmod 600 ~/.ssh/id_rsa*"

echo $(date) "- Configuring SSH ControlPath to use shorter path name"

sed -i -e "s/^# control_path = %(directory)s\/%%h-%%r/control_path = %(directory)s\/%%h-%%r/" /etc/ansible/ansible.cfg
sed -i -e "s/^#host_key_checking = False/host_key_checking = False/" /etc/ansible/ansible.cfg
sed -i -e "s/^#pty=False/pty=False/" /etc/ansible/ansible.cfg

# Create playbook to update ansible.cfg file

cat > updateansiblecfg.yaml <<EOF
#!/usr/bin/ansible-playbook

- hosts: localhost
  gather_facts: no
  tasks:
  - lineinfile:
      dest: /etc/ansible/ansible.cfg
      regexp: '^library '
      insertafter: '#library        = /usr/share/my_modules/'
      line: 'library = /home/${SUDOUSER}/openshift-ansible/library/'
EOF

# Run Ansible Playbook to update ansible.cfg file

echo $(date) " - Updating ansible.cfg file"

ansible-playbook ./updateansiblecfg.yaml

# Create Ansible Playbooks for Post Installation tasks
echo $(date) " - Create Ansible Playbooks for Post Installation tasks"

# Run on all masters - Create Inital OpenShift User on all Masters

cat > /home/${SUDOUSER}/addocpuser.yml <<EOF
---
- hosts: masters
  gather_facts: no
  become: yes
  become_method: sudo
  vars:
    description: "Create OpenShift Users"
  tasks:
  - name: create directory
    file: path=/etc/origin/master state=directory
  - name: add initial OpenShift user
    shell: "htpasswd -cb /etc/origin/master/htpasswd {{ lookup('env','SUDOUSER') }} \"{{ lookup('env','PASSWORD') }}\""
EOF

# Run on MASTER-0 - Make initial OpenShift User a Cluster Admin

cat > /home/${SUDOUSER}/assignclusteradminrights.yml <<EOF
---
- hosts: master0
  gather_facts: no
  become: yes
  become_method: sudo
  vars:
    description: "Make user cluster admin"
  tasks:
  - name: make OpenShift user cluster admin
    shell: "oadm policy add-cluster-role-to-user cluster-admin {{ lookup('env','SUDOUSER') }} --config=/etc/origin/master/admin.kubeconfig"
EOF


# Run on MASTER-0 node - configure registry to use Azure Storage
# Create docker registry config based on Commercial Azure or Azure Government

if [[ $CLOUD == "US" ]]
then

cat > /home/${SUDOUSER}/dockerregistry.yml <<EOF
---
- hosts: master0
  gather_facts: no
  become: yes
  become_method: sudo
  vars:
    description: "Set registry to use Azure Storage"
  tasks:
  - name: Configure docker-registry to use Azure Storage
    shell: oc env dc docker-registry -e REGISTRY_STORAGE=azure -e REGISTRY_STORAGE_AZURE_ACCOUNTNAME=$REGISTRYSA -e REGISTRY_STORAGE_AZURE_ACCOUNTKEY=$ACCOUNTKEY -e REGISTRY_STORAGE_AZURE_CONTAINER=registry -e REGISTRY_STORAGE_AZURE_REALM=core.usgovcloudapi.net
EOF

export CLOUDNAME="AzureUSGovernmentCloud"

else

cat > /home/${SUDOUSER}/dockerregistry.yml <<EOF
---
- hosts: master0
  gather_facts: no
  become: yes
  become_method: sudo
  vars:
    description: "Set registry to use Azure Storage"
  tasks:
  - name: Configure docker-registry to use Azure Storage
    shell: oc env dc docker-registry -e REGISTRY_STORAGE=azure -e REGISTRY_STORAGE_AZURE_ACCOUNTNAME=$REGISTRYSA -e REGISTRY_STORAGE_AZURE_ACCOUNTKEY=$ACCOUNTKEY -e REGISTRY_STORAGE_AZURE_CONTAINER=registry
EOF

export CLOUDNAME="AzurePublicCloud"

fi

# Run on MASTER-0 - configure Storage Class

cat > /home/${SUDOUSER}/configurestorageclass.yml <<EOF
---
- hosts: master0
  gather_facts: no
  become: yes
  become_method: sudo
  vars:
    description: "Create Storage Class"
    storage: "{{ lookup('env','STORAGEKIND') }}"
  tasks:
  - name: Create unmanaged storage class
    shell: oc create -f /home/{{ lookup('env','SUDOUSER') }}/scunmanaged.yml
    when: storage == 'unmanaged'

  - name: Create managed storage class
    shell: oc create -f /home/{{ lookup('env','SUDOUSER') }}/scmanaged.yml
    when: storage == 'managed'
EOF

# Create playbook to reboot infra and app nodes

cat > /home/${SUDOUSER}/reboot-nodes.yml <<EOF
---
- hosts: nodes:!masters
  gather_facts: no
  become: yes
  become_method: sudo
  tasks:
  - name: Reboot infra and app nodes
    shell: (/bin/sleep 5 ; shutdown -r now "OpenShift configurations required reboot" ) &
    async: 30
    poll: 0
    ignore_errors: true

  - name: Wait for infra and app nodes to reboot
    wait_for:
      port: 22
      host: "{{ ansible_ssh_host|default(inventory_hostname) }}"
      delay: 10
      timeout: 180
    connection: local
    become: false
EOF

# Create Azure Cloud Provider configuration Playbook for Master Config

cat > /home/${SUDOUSER}/setup-azure-master.yml <<EOF
#!/usr/bin/ansible-playbook
- hosts: masters
  gather_facts: no
  serial: 1
  become: yes
  vars:
    azure_conf_dir: /etc/azure
    azure_conf: "{{ azure_conf_dir }}/azure.conf"
    master_conf: /etc/origin/master/master-config.yaml
  handlers:
  - name: restart origin-master-api
    systemd:
      state: restarted
      name: origin-master-api

  - name: restart origin-master-controllers
    systemd:
      state: restarted
      name: origin-master-controllers

  post_tasks:
  - name: make sure /etc/azure exists
    file:
      state: directory
      path: "{{ azure_conf_dir }}"

  - name: populate /etc/azure/azure.conf
    copy:
      dest: "{{ azure_conf }}"
      content: |
        {
          "aadClientId": "{{ lookup('env','AADCLIENTID') }}",
          "aadClientSecret": "{{ lookup('env','AADCLIENTSECRET') }}",
          "aadTenantId": "{{ lookup('env','TENANTID') }}",
          "subscriptionId": "{{ lookup('env','SUBSCRIPTIONID') }}",
          "tenantId": "{{ lookup('env','TENANTID') }}",
          "resourceGroup": "{{ lookup('env','RESOURCEGROUP') }}",
          "location": "{{ lookup('env','LOCATION') }}",
          "cloud": "{{ lookup('env','CLOUDNAME') }}"
        } 
    notify:
    - restart origin-master-api
    - restart origin-master-controllers

  - name: insert the azure disk config into the master
    modify_yaml:
      dest: "{{ master_conf }}"
      yaml_key: "{{ item.key }}"
      yaml_value: "{{ item.value }}"
    with_items:
    - key: kubernetesMasterConfig.apiServerArguments.cloud-config
      value:
      - "{{ azure_conf }}"

    - key: kubernetesMasterConfig.apiServerArguments.cloud-provider
      value:
      - azure

    - key: kubernetesMasterConfig.controllerArguments.cloud-config
      value:
      - "{{ azure_conf }}"

    - key: kubernetesMasterConfig.controllerArguments.cloud-provider
      value:
      - azure
    notify:
    - restart origin-master-api
    - restart origin-master-controllers
EOF

# Create Azure Cloud Provider configuration Playbook for Node Config (Master Nodes)

cat > /home/${SUDOUSER}/setup-azure-node-master.yml <<EOF
#!/usr/bin/ansible-playbook
- hosts: masters
  serial: 1
  gather_facts: no
  become: yes
  vars:
    azure_conf_dir: /etc/azure
    azure_conf: "{{ azure_conf_dir }}/azure.conf"
    node_conf: /etc/origin/node/node-config.yaml
  handlers:
  - name: restart origin-node
    systemd:
      state: restarted
      name: origin-node
  post_tasks:
  - name: make sure /etc/azure exists
    file:
      state: directory
      path: "{{ azure_conf_dir }}"

  - name: populate /etc/azure/azure.conf
    copy:
      dest: "{{ azure_conf }}"
      content: |
        {
          "aadClientId": "{{ lookup('env','AADCLIENTID') }}",
          "aadClientSecret": "{{ lookup('env','AADCLIENTSECRET') }}",
          "aadTenantId": "{{ lookup('env','TENANTID') }}",
          "subscriptionId": "{{ lookup('env','SUBSCRIPTIONID') }}",
          "tenantId": "{{ lookup('env','TENANTID') }}",
          "resourceGroup": "{{ lookup('env','RESOURCEGROUP') }}",
          "location": "{{ lookup('env','LOCATION') }}",
          "cloud": "{{ lookup('env','CLOUDNAME') }}"
        } 
    notify:
    - restart origin-node
  - name: insert the azure disk config into the node
    modify_yaml:
      dest: "{{ node_conf }}"
      yaml_key: "{{ item.key }}"
      yaml_value: "{{ item.value }}"
    with_items:
    - key: kubeletArguments.cloud-config
      value:
      - "{{ azure_conf }}"

    - key: kubeletArguments.cloud-provider
      value:
      - azure
    notify:
    - restart origin-node
EOF

# Create Azure Cloud Provider configuration Playbook for Node Config (Non-Master Nodes)

cat > /home/${SUDOUSER}/setup-azure-node.yml <<EOF
#!/usr/bin/ansible-playbook
- hosts: nodes:!masters
  serial: 1
  gather_facts: no
  become: yes
  vars:
    azure_conf_dir: /etc/azure
    azure_conf: "{{ azure_conf_dir }}/azure.conf"
    node_conf: /etc/origin/node/node-config.yaml
  handlers:
  - name: restart origin-node
    systemd:
      state: restarted
      name: origin-node
  post_tasks:
  - name: make sure /etc/azure exists
    file:
      state: directory
      path: "{{ azure_conf_dir }}"

  - name: populate /etc/azure/azure.conf
    copy:
      dest: "{{ azure_conf }}"
      content: |
        {
          "aadClientId": "{{ lookup('env','AADCLIENTID') }}",
          "aadClientSecret": "{{ lookup('env','AADCLIENTSECRET') }}",
          "aadTenantId": "{{ lookup('env','TENANTID') }}",
          "subscriptionId": "{{ lookup('env','SUBSCRIPTIONID') }}",
          "tenantId": "{{ lookup('env','TENANTID') }}",
          "resourceGroup": "{{ lookup('env','RESOURCEGROUP') }}",
          "location": "{{ lookup('env','LOCATION') }}",
          "cloud": "{{ lookup('env','CLOUDNAME') }}"
        } 
    notify:
    - restart origin-node
  - name: insert the azure disk config into the node
    modify_yaml:
      dest: "{{ node_conf }}"
      yaml_key: "{{ item.key }}"
      yaml_value: "{{ item.value }}"
    with_items:
    - key: kubeletArguments.cloud-config
      value:
      - "{{ azure_conf }}"

    - key: kubeletArguments.cloud-provider
      value:
      - azure
    notify:
    - restart origin-node
EOF

# Create Playbook to set Master nodes as not schedulable

cat > /home/${SUDOUSER}/masternonschedulable.yml <<EOF
- hosts: masters
  gather_facts: no
  become: yes
  vars:
    description: "Set masters as non-schedulable"
  tasks:
  - name: set masters as unschedulable
    command: oadm manage-node {{inventory_hostname}} --schedulable=false
EOF

# Create Ansible Hosts File
echo $(date) " - Create Ansible Hosts file"

cat > /etc/ansible/hosts <<EOF
# Create an OSEv3 group that contains the masters and nodes groups
[OSEv3:children]
masters
nodes
etcd
master0
new_nodes

# Set variables common for all OSEv3 hosts
[OSEv3:vars]
ansible_ssh_user=$SUDOUSER
ansible_become=yes
openshift_install_examples=true
openshift_deployment_type=origin
openshift_release=v3.7
docker_udev_workaround=True
openshift_use_dnsmasq=True
openshift_master_default_subdomain=$ROUTING
openshift_override_hostname_check=true
osm_use_cockpit=false
os_sdn_network_plugin_name='redhat/openshift-ovs-multitenant'
#console_port=443
openshift_cloudprovider_kind=azure
osm_default_node_selector='type=app'
openshift_disable_check=disk_availability,memory_availability
# default selectors for router and registry services
openshift_router_selector='type=infra'
openshift_registry_selector='type=infra'

openshift_master_cluster_method=native
openshift_master_cluster_hostname=$MASTERPUBLICIPHOSTNAME
openshift_master_cluster_public_hostname=$MASTERPUBLICIPHOSTNAME
openshift_master_cluster_public_vip=$MASTERPUBLICIPADDRESS

# Enable HTPasswdPasswordIdentityProvider
openshift_master_identity_providers=[{'name': 'htpasswd_auth', 'login': 'true', 'challenge': 'true', 'kind': 'HTPasswdPasswordIdentityProvider', 'filename': '/etc/origin/master/htpasswd'}]

# Enable service catalog
# openshift_enable_service_catalog=false
# Enable template service broker (requires service catalog to be enabled, above)
# template_service_broker_install=false
# Configure one of more namespaces whose templates will be served by the TSB
openshift_template_service_broker_namespaces=['openshift']
# Disable the OpenShift SDN plugin
openshift_use_openshift_sdn=true

# Setup metrics
openshift_metrics_install_metrics=false
#openshift_metrics_cassandra_storage_type=dynamic
openshift_metrics_start_cluster=true
openshift_metrics_startup_timeout=120
openshift_metrics_hawkular_nodeselector={"type":"infra"}
openshift_metrics_cassandra_nodeselector={"type":"infra"}
openshift_metrics_heapster_nodeselector={"type":"infra"}
openshift_hosted_metrics_public_url=https://metrics.$ROUTING/hawkular/metrics

# Setup logging
openshift_logging_install_logging=false
#openshift_logging_es_pvc_dynamic=true
openshift_logging_es_pvc_storage_class_name=generic
openshift_logging_fluentd_nodeselector={"logging":"true"}
openshift_logging_es_nodeselector={"type":"infra"}
openshift_logging_kibana_nodeselector={"type":"infra"}
openshift_logging_curator_nodeselector={"type":"infra"}
openshift_master_logging_public_url=https://kibana.$ROUTING
openshift_logging_master_public_url=https://$MASTERPUBLICIPHOSTNAME:8443

# host group for masters
[masters]
$MASTER-[0:${MASTERLOOP}]

# host group for etcd
[etcd]
$MASTER-[0:${MASTERLOOP}]

[master0]
$MASTER-0

# host group for nodes
[nodes]
EOF

# Loop to add Masters

for (( c=0; c<$MASTERCOUNT; c++ ))
do
  echo "$MASTER-$c openshift_node_labels=\"{'type': 'master', 'zone': 'default'}\" openshift_hostname=$MASTER-$c" >> /etc/ansible/hosts
done

# Loop to add Infra Nodes

for (( c=0; c<$INFRACOUNT; c++ ))
do
  echo "$INFRA-$c openshift_node_labels=\"{'type': 'infra', 'zone': 'default', 'region': 'infra'}\" openshift_hostname=$INFRA-$c" >> /etc/ansible/hosts
done

# Loop to add Nodes

for (( c=0; c<$NODECOUNT; c++ ))
do
  echo "$NODE-$c openshift_node_labels=\"{'type': 'app', 'zone': 'default'}\" openshift_hostname=$NODE-$c" >> /etc/ansible/hosts
done

# Create new_nodes group

cat >> /etc/ansible/hosts <<EOF

# host group for adding new nodes
[new_nodes]
EOF

echo $(date) " - Cloning openshift-ansible repo for use in installation"

runuser -l $SUDOUSER -c "git clone -b release-3.7 https://github.com/openshift/openshift-ansible /home/$SUDOUSER/openshift-ansible"

echo $(date) " - Running network_manager.yml playbook"
DOMAIN=`domainname -d`

# Setup NetworkManager to manage eth0
runuser -l $SUDOUSER -c "ansible-playbook openshift-ansible/playbooks/byo/openshift-node/network_manager.yml"

echo $(date) " - Setting up NetworkManager on eth0"
# Configure resolv.conf on all hosts through NetworkManager

runuser -l $SUDOUSER -c "ansible all -b -m service -a \"name=NetworkManager state=restarted\""
sleep 5
runuser -l $SUDOUSER -c "ansible all -b -m command -a \"nmcli con modify eth0 ipv4.dns-search $DOMAIN\""
runuser -l $SUDOUSER -c "ansible all -b -m service -a \"name=NetworkManager state=restarted\""

# Initiating installation of OpenShift Container Platform using Ansible Playbook
echo $(date) " - Installing OpenShift Container Platform via Ansible Playbook"

runuser -l $SUDOUSER -c "ansible-playbook openshift-ansible/playbooks/byo/config.yml"

echo $(date) " - Modifying sudoers"

sed -i -e "s/Defaults    requiretty/# Defaults    requiretty/" /etc/sudoers
sed -i -e '/Defaults    env_keep += "LC_TIME LC_ALL LANGUAGE LINGUAS _XKB_CHARSET XAUTHORITY"/aDefaults    env_keep += "PATH"' /etc/sudoers

echo $(date) "- Re-enabling requiretty"

sed -i -e "s/# Defaults    requiretty/Defaults    requiretty/" /etc/sudoers

# Adding user to OpenShift authentication file
echo $(date) "- Adding OpenShift user"

runuser $SUDOUSER -c "ansible-playbook ~/addocpuser.yml"

# Assigning cluster admin rights to OpenShift user
echo $(date) "- Assigning cluster admin rights to user"

runuser $SUDOUSER -c "ansible-playbook ~/assignclusteradminrights.yml"

# Configure Docker Registry to use Azure Storage Account
echo $(date) "- Configuring Docker Registry to use Azure Storage Account"

runuser $SUDOUSER -c "ansible-playbook ~/dockerregistry.yml"

if [[ $AZURE == "true" ]]
then

	# Create Storage Classes
	echo $(date) "- Creating Storage Classes"

	runuser $SUDOUSER -c "ansible-playbook ~/configurestorageclass.yml"

	echo $(date) "- Sleep for 120"

	sleep 120

	# Execute setup-azure-master and setup-azure-node playbooks to configure Azure Cloud Provider
	echo $(date) "- Configuring OpenShift Cloud Provider to be Azure"

	runuser $SUDOUSER -c "ansible-playbook ~/setup-azure-master.yml"

	if [ $? -eq 0 ]
	then
	   echo $(date) " - Cloud Provider setup of master config on Master Nodes completed successfully"
	else
	   echo $(date) "- Cloud Provider setup of master config on Master Nodes failed to completed"
	   exit 7
	fi
	
	echo $(date) "- Sleep for 60"
	
	sleep 60
	runuser $SUDOUSER -c "ansible-playbook ~/setup-azure-node-master.yml"

	if [ $? -eq 0 ]
	then
	   echo $(date) " - Cloud Provider setup of node config on Master Nodes completed successfully"
	else
	   echo $(date) "- Cloud Provider setup of node config on Master Nodes failed to completed"
	   exit 8
	fi
	
	echo $(date) "- Sleep for 60"
	
	sleep 60
	runuser $SUDOUSER -c "ansible-playbook ~/setup-azure-node.yml"

	if [ $? -eq 0 ]
	then
	   echo $(date) " - Cloud Provider setup of node config on App Nodes completed successfully"
	else
	   echo $(date) "- Cloud Provider setup of node config on App Nodes failed to completed"
	   exit 9
	fi
	
	echo $(date) "- Sleep for 120"
	
	sleep 120
	runuser $SUDOUSER -c "ansible-playbook ~/masternonschedulable.yml"

	if [ $? -eq 0 ]
	then
	   echo $(date) " - Cloud Provider setup of OpenShift Cluster completed successfully"
	else
	   echo $(date) "- Cloud Provider setup failed to delete stuck Master nodes or was not able to set them as unschedulable"
	   exit 10
	fi

	echo $(date) "- Restarting OVS to complete installation"
	
	echo $(date) "- Sleep for 20"
	
	sleep 20
	runuser -l $SUDOUSER -c  "oc label nodes $MASTER-0 openshift-infra=apiserver --overwrite=true"	
	runuser -l $SUDOUSER -c  "oc label nodes --all logging-infra-fluentd=true logging=true"

	runuser -l $SUDOUSER -c  "ansible all -b  -m service -a 'name=openvswitch state=restarted' "

	echo $(date) "- Restarting origin nodes after 20 seconds"
	sleep 20

	runuser -l $SUDOUSER -c  "ansible nodes -b  -m service -a 'name=origin-node state=restarted' "
	sleep 10
	runuser -l $SUDOUSER -c "oc rollout latest dc/asb -n openshift-ansible-service-broker"
	runuser -l $SUDOUSER -c "oc rollout latest dc/asb-etcd -n openshift-ansible-service-broker"

fi

# Configure Metrics

if [ $METRICS == "true" ]
then
	sleep 30	
	echo $(date) "- Determining Origin version from rpm"
	OO_VERSION=$(rpm -q origin | cut -d'-' -f 2)	
	echo $(date) "- Deploying Metrics"
	if [ $AZURE == "true" ]
	then
		runuser -l $SUDOUSER -c "ansible-playbook /home/$SUDOUSER/openshift-ansible/playbooks/byo/openshift-cluster/openshift-metrics.yml -e openshift_metrics_install_metrics=True -e openshift_metrics_cassandra_storage_type=dynamic -e openshift_hosted_metrics_deployer_version=$OO_VERSION"
	else
		runuser -l $SUDOUSER -c "ansible-playbook /home/$SUDOUSER/openshift-ansible/playbooks/byo/openshift-cluster/openshift-metrics.yml -e openshift_metrics_install_metrics=True -e openshift_hosted_metrics_deployer_version=$OO_VERSION"
	fi
	if [ $? -eq 0 ]
	then
	   echo $(date) " - Metrics configuration completed successfully"
	else
	   echo $(date) "- Metrics configuration failed"
	   exit 11
	fi
fi

# Configure Logging

if [ $LOGGING == "true" ] 
then
	sleep 60
	echo $(date) "- Deploying Logging"
	if [ $AZURE == "true" ]
	then
		runuser -l $SUDOUSER -c "ansible-playbook /home/$SUDOUSER/openshift-ansible/playbooks/byo/openshift-cluster/openshift-logging.yml -e openshift_logging_install_logging=True -e openshift_logging_es_pvc_dynamic=true"
	else
		runuser -l $SUDOUSER -c "ansible-playbook /home/$SUDOUSER/openshift-ansible/playbooks/byo/openshift-cluster/openshift-logging.yml -e openshift_logging_install_logging=True"
	fi
	if [ $? -eq 0 ]
	then
	   echo $(date) " - Logging configuration completed successfully"
	else
	   echo $(date) "- Logging configuration failed"
	   exit 12
	fi
fi
# Delete postinstall files
echo $(date) "- Deleting post installation files"


rm /home/${SUDOUSER}/addocpuser.yml
rm /home/${SUDOUSER}/assignclusteradminrights.yml
rm /home/${SUDOUSER}/dockerregistry.yml
rm /home/${SUDOUSER}/setup-azure-master.yml
rm /home/${SUDOUSER}/setup-azure-node-master.yml
rm /home/${SUDOUSER}/setup-azure-node.yml
rm /home/${SUDOUSER}/masternonschedulable.yml
rm /home/${SUDOUSER}/reboot-nodes.yml

echo $(date) " - Script complete"
