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
export AZURE=${23}
export STORAGEKIND=${24}

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
sed -i -e "s/^#stdout_callback = skippy/stdout_callback = skippy/" /etc/ansible/ansible.cfg

sed -i -e "s/^#timeout = 10/timeout = 40/" /etc/ansible/ansible.cfg

# Cloning Ansible playbook repository
((cd /home/$SUDOUSER && git clone https://github.com/Microsoft/openshift-container-platform-playbooks.git) || (cd openshift-container-platform-playbooks && git pull))
if [ -d /home/${SUDOUSER}/openshift-container-platform-playbooks ]
then
  echo " - Retrieved playbooks successfully"
else
  echo " - Retrieval of playbooks failed"
  exit 99
fi

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
      line: 'library = /home/${SUDOUSER}/openshift-ansible/roles/lib_utils/library/'
EOF

# Run Ansible Playbook to update ansible.cfg file

echo $(date) " - Updating ansible.cfg file"

ansible-playbook ./updateansiblecfg.yaml

# Create docker registry config based on Commercial Azure or Azure Government
if [[ $CLOUD == "US" ]]
then
  DOCKERREGISTRYYAML=dockerregistrygov.yaml
  export CLOUDNAME="AzureUSGovernmentCloud"
else
  DOCKERREGISTRYYAML=dockerregistrypublic.yaml
  export CLOUDNAME="AzurePublicCloud"
fi

# Create Master nodes grouping
echo $(date) " - Creating Master nodes grouping"

for (( c=0; c<$MASTERCOUNT; c++ ))
do
  mastergroup="$mastergroup
$MASTER-$c openshift_node_labels=\"{'region': 'master', 'zone': 'default'}\" openshift_hostname=$MASTER-$c"
done

# Create Infra nodes grouping 
echo $(date) " - Creating Infra nodes grouping"

for (( c=0; c<$INFRACOUNT; c++ ))
do
  infragroup="$infragroup
$INFRA-$c openshift_node_labels=\"{'region': 'infra', 'zone': 'default'}\" openshift_hostname=$INFRA-$c"
done

# Create Nodes grouping
echo $(date) " - Creating Nodes grouping"

for (( c=0; c<$NODECOUNT; c++ ))
do
  nodegroup="$nodegroup
$NODE-$c openshift_node_labels=\"{'region': 'app', 'zone': 'default'}\" openshift_hostname=$NODE-$c"
done

# Set HA mode if 3 or 5 masters chosen
if [[ $MASTERCOUNT != 1 ]]
then
	export HAMODE="openshift_master_cluster_method=native"
fi

# Setting the default openshift_cloudprovider_kind if Azure enabled
if [[ $AZURE == "true" ]]
then
	export CLOUDKIND="openshift_cloudprovider_kind=azure
osm_controller_args={'cloud-provider': ['azure'], 'cloud-config': ['/etc/origin/cloudprovider/azure.conf']}
osm_api_server_args={'cloud-provider': ['azure'], 'cloud-config': ['/etc/origin/cloudprovider/azure.conf']}
openshift_node_kubelet_args={'cloud-provider': ['azure'], 'cloud-config': ['/etc/origin/cloudprovider/azure.conf'], 'enable-controller-attach-detach': ['true']}"
fi

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
openshift_release=v3.11
docker_udev_workaround=True
openshift_use_dnsmasq=True
openshift_master_default_subdomain=$ROUTING
openshift_override_hostname_check=true
os_sdn_network_plugin_name='redhat/openshift-ovs-multitenant'
openshift_master_api_port=443
openshift_master_console_port=443
osm_default_node_selector='region=app'
openshift_disable_check=disk_availability,memory_availability,docker_image_availability
$CLOUDKIND

# default selectors for router and registry services
openshift_router_selector='region=infra'
openshift_registry_selector='region=infra'

$HAMODE
openshift_master_cluster_hostname=$MASTERPUBLICIPHOSTNAME
openshift_master_cluster_public_hostname=$MASTERPUBLICIPHOSTNAME
openshift_master_cluster_public_vip=$MASTERPUBLICIPADDRESS

# Enable HTPasswdPasswordIdentityProvider
openshift_master_identity_providers=[{'name': 'htpasswd_auth', 'login': 'true', 'challenge': 'true', 'kind': 'HTPasswdPasswordIdentityProvider', 'filename': '/etc/origin/master/htpasswd'}]

# Disable service catalog - Install after cluster is up if Azure Cloud Provider is enabled
openshift_enable_service_catalog=false

# Disable the OpenShift SDN plugin
# openshift_use_openshift_sdn=true

# Setup metrics
openshift_metrics_install_metrics=false
#openshift_metrics_cassandra_storage_type=dynamic
openshift_metrics_start_cluster=true
openshift_metrics_startup_timeout=120
openshift_metrics_hawkular_nodeselector={"region":"infra"}
openshift_metrics_cassandra_nodeselector={"region":"infra"}
openshift_metrics_heapster_nodeselector={"region":"infra"}
# openshift_metrics_hawkular_hostname=https://hawkular-metrics.$ROUTING/hawkular/metrics

# Setup logging
openshift_logging_install_logging=false
# openshift_logging_es_pvc_dynamic=true
openshift_logging_es_pvc_storage_class_name=generic
openshift_logging_fluentd_nodeselector={"logging":"true"}
openshift_logging_es_nodeselector={"region":"infra"}
openshift_logging_kibana_nodeselector={"region":"infra"}
openshift_logging_curator_nodeselector={"region":"infra"}
openshift_master_logging_public_url=https://kibana.$ROUTING
openshift_logging_master_public_url=https://$MASTERPUBLICIPHOSTNAME:443

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
$mastergroup
$infragroup
$nodegroup

# host group for new nodes
[new_nodes]
EOF

echo $(date) " - Cloning openshift-ansible repo for use in installation"

runuser -l $SUDOUSER -c "git clone -b release-3.11 https://github.com/openshift/openshift-ansible /home/$SUDOUSER/openshift-ansible"
chmod -R 777 /home/$SUDOUSER/openshift-ansible

# Run a loop playbook to ensure DNS Hostname resolution is working prior to continuing with script
echo $(date) " - Running DNS Hostname resolution check"
runuser -l $SUDOUSER -c "ansible-playbook ~/openshift-container-platform-playbooks/check-dns-host-name-resolution.yaml"
echo $(date) " - DNS Hostname resolution check complete"

# Setup NetworkManager to manage eth0
echo $(date) " - Setting up NetworkManager on eth0"
DOMAIN=`domainname -d`
DNSSERVER=`tail -1 /etc/resolv.conf | cut -d ' ' -f 2`

runuser -l $SUDOUSER -c "ansible-playbook /home/$SUDOUSER/openshift-ansible/playbooks/openshift-node/network_manager.yml"

sleep 10
runuser -l $SUDOUSER -c "ansible all -b -o -m service -a \"name=NetworkManager state=restarted\""
sleep 10
runuser -l $SUDOUSER -c "ansible all -b -o -m command -a \"nmcli con modify eth0 ipv4.dns-search $DOMAIN, ipv4.dns $DNSSERVER\""
runuser -l $SUDOUSER -c "ansible all -b -o -m service -a \"name=NetworkManager state=restarted\""
echo $(date) " - NetworkManager configuration complete"

# Create /etc/origin/cloudprovider/azure.conf on all hosts if Azure is enabled
if [[ $AZURE == "true" ]]
then
	runuser $SUDOUSER -c "ansible-playbook -f 10 ~/openshift-container-platform-playbooks/create-azure-conf.yaml"
	if [ $? -eq 0 ]
	then
		echo $(date) " - Creation of Cloud Provider Config (azure.conf) completed on all nodes successfully"
	else
		echo $(date) " - Creation of Cloud Provider Config (azure.conf) completed on all nodes failed to complete"
		exit 13
	fi
fi

# Initiating installation of OpenShift Origin prerequisites using Ansible Playbook
echo $(date) " - Running Prerequisites via Ansible Playbook"
runuser -l $SUDOUSER -c "ansible-playbook -f 10 /home/$SUDOUSER/openshift-ansible/playbooks/prerequisites.yml"
echo $(date) " - Prerequisites check complete"

# Initiating installation of OpenShift Origin using Ansible Playbook
echo $(date) " - Installing OpenShift Container Platform via Ansible Playbook"

runuser -l $SUDOUSER -c "ansible-playbook -f 10 /home/$SUDOUSER/openshift-ansible/playbooks/deploy_cluster.yml"
echo $(date) " - OpenShift Origin Cluster install complete"
echo $(date) " - Running additional playbooks to finish configuring and installing other components"

echo $(date) " - Modifying sudoers"

sed -i -e "s/Defaults    requiretty/# Defaults    requiretty/" /etc/sudoers
sed -i -e '/Defaults    env_keep += "LC_TIME LC_ALL LANGUAGE LINGUAS _XKB_CHARSET XAUTHORITY"/aDefaults    env_keep += "PATH"' /etc/sudoers

echo $(date) "- Re-enabling requiretty"

sed -i -e "s/# Defaults    requiretty/Defaults    requiretty/" /etc/sudoers

# Adding user to OpenShift authentication file
echo $(date) "- Adding OpenShift user"

runuser $SUDOUSER -c "ansible-playbook -f 10 ~/openshift-container-platform-playbooks/addocpuser.yaml"

# Assigning cluster admin rights to OpenShift user
echo $(date) "- Assigning cluster admin rights to user"

runuser $SUDOUSER -c "ansible-playbook -f 10 ~/openshift-container-platform-playbooks/assignclusteradminrights.yaml"

# Configure Docker Registry to use Azure Storage Account
echo $(date) "- Configuring Docker Registry to use Azure Storage Account"

runuser $SUDOUSER -c "ansible-playbook -f 10 ~/openshift-container-platform-playbooks/$DOCKERREGISTRYYAML"

if [[ $AZURE == "true" ]]
then
	echo $(date) " - Rebooting cluster to complete installation"
	runuser -l $SUDOUSER -c  "oc label --overwrite nodes $MASTER-0 openshift-infra=apiserver"
	runuser -l $SUDOUSER -c  "oc label --overwrite nodes --all logging-infra-fluentd=true logging=true"
	runuser -l $SUDOUSER -c  "ansible localhost -b -o -m service -a 'name=openvswitch state=restarted'"
	runuser -l $SUDOUSER -c  "ansible localhost -b -o -m service -a 'name=origin-master-api state=restarted'"
	runuser -l $SUDOUSER -c  "ansible localhost -b -o -m service -a 'name=origin-master-controllers state=restarted'"
	runuser -l $SUDOUSER -c  "ansible localhost -b -o -m service -a 'name=origin-node state=restarted'"
	runuser -l $SUDOUSER -c "ansible-playbook -f 10 ~/openshift-container-platform-playbooks/reboot-master-origin.yaml"
	runuser -l $SUDOUSER -c "ansible-playbook -f 10 ~/openshift-container-platform-playbooks/reboot-nodes.yaml"

	if [ $? -eq 0 ]
	then
	   echo $(date) " - Cloud Provider setup of OpenShift Cluster completed successfully"
	else
	   echo $(date) "- Cloud Provider setup did not complete"
	   exit 10
	fi
	
	# Create Storage Class
	echo $(date) "- Creating Storage Class"

	runuser $SUDOUSER -c "ansible-playbook -f 10 ~/openshift-container-platform-playbooks/configurestorageclass.yaml"
	echo $(date) "- Sleep for 15"
	sleep 15
	
	# Installing Service Catalog, Ansible Service Broker and Template Service Broker
	
	echo $(date) "- Installing Service Catalog, Ansible Service Broker and Template Service Broker"
	runuser -l $SUDOUSER -c "ansible-playbook -f 10 /home/$SUDOUSER/openshift-ansible/playbooks/openshift-service-catalog/config.yml"
	echo $(date) "- Service Catalog, Ansible Service Broker and Template Service Broker installed successfully"
	
fi

# Configure Metrics

if [ $METRICS == "true" ]
then
	sleep 30	
	echo $(date) "- Determining Origin version from rpm"
	OO_VERSION="v"$(rpm -q origin | cut -d'-' -f 2 | head -c 3)
	echo $(date) "- Deploying Metrics"
	if [ $AZURE == "true" ]
	then
		runuser -l $SUDOUSER -c "ansible-playbook -f 10 /home/$SUDOUSER/openshift-ansible/playbooks/openshift-metrics/config.yml -e openshift_metrics_install_metrics=True -e openshift_metrics_cassandra_storage_type=dynamic -e openshift_metrics_image_version=$OO_VERSION"
	else
		runuser -l $SUDOUSER -c "ansible-playbook -f 10 /home/$SUDOUSER/openshift-ansible/playbooks/openshift-metrics/config.yml -e openshift_metrics_install_metrics=True -e openshift_metrics_image_version=$OO_VERSION"
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
		runuser -l $SUDOUSER -c "ansible-playbook -f 10 /home/$SUDOUSER/openshift-ansible/playbooks/openshift-logging/config.yml -e openshift_logging_install_logging=True -e openshift_logging_es_pvc_dynamic=true -e openshift_master_dynamic_provisioning_enabled=True"
	else
		runuser -l $SUDOUSER -c "ansible-playbook -f 10 /home/$SUDOUSER/openshift-ansible/playbooks/openshift-logging/config.yml -e openshift_logging_install_logging=True"
	fi
	if [ $? -eq 0 ]
	then
	   echo $(date) " - Logging configuration completed successfully"
	else
	   echo $(date) "- Logging configuration failed"
	   exit 12
	fi
fi

# Delete yaml files
echo $(date) "- Deleting unecessary files"

rm -rf /home/${SUDOUSER}/openshift-container-platform-playbooks

echo $(date) "- Sleep for 30"

sleep 30

echo $(date) " - Script complete"
