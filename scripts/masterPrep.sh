#!/bin/bash
echo $(date) " - Starting Script"

STORAGEACCOUNT1=$1
SUDOUSER=$2

# Update system to latest packages and install dependencies
echo $(date) " - Update system to latest packages and install dependencies"

yum -y install wget git net-tools bind-utils iptables-services bridge-utils bash-completion httpd-tools
yum -y update --exclude=WALinuxAgent

# Install EPEL repository
echo $(date) " - Installing EPEL"

yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm

sed -i -e "s/^enabled=1/enabled=0/" /etc/yum.repos.d/epel.repo

# Only install Ansible and pyOpenSSL on Master-0 Node

if hostname -f|grep -- "-0" >/dev/null
then
   echo $(date) " - Installing Ansible and pyOpenSSL"
   yum -y --enablerepo=epel install ansible pyOpenSSL
fi

# Install Docker 1.12.x
echo $(date) " - Installing Docker 1.12.x"

yum -y install docker
sed -i -e "s#^OPTIONS='--selinux-enabled'#OPTIONS='--selinux-enabled --insecure-registry 172.30.0.0/16'#" /etc/sysconfig/docker

# Create thin pool logical volume for Docker
echo $(date) " - Creating thin pool logical volume for Docker and staring service"

DOCKERVG=$( parted -m /dev/sda print all 2>/dev/null | grep unknown | grep /dev/sd | cut -d':' -f1 )

echo "DEVS=${DOCKERVG}" >> /etc/sysconfig/docker-storage-setup
echo "VG=docker-vg" >> /etc/sysconfig/docker-storage-setup
docker-storage-setup
if [ $? -eq 0 ]
then
   echo "Docker thin pool logical volume created successfully"
else
   echo "Error creating logical volume for Docker"
   exit 5
fi

# Enable and start Docker services

systemctl enable docker
systemctl start docker

# Create Storage Class yml files on MASTER-0

if hostname -f|grep -- "-0" >/dev/null
then
cat <<EOF > /home/${SUDOUSER}/scgeneric1.yml
kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: generic
  annotations:
    storageclass.beta.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/azure-disk
parameters:
  storageAccount: ${STORAGEACCOUNT1}
EOF

# Install Azure CLI

echo $(date) " - Installing Azure CLI"

yum -y --enablerepo=epel install nodejs

npm install -g azure-cli

fi

echo $(date) " - Script Complete"
