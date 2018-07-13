This CHANGELOG.md file will contain the update log for the latest set of updates to the templates

# UPDATES for Origin 3.9 - July 13, 2018

1.  Use CentOS 7.5 image.
2.  Adjust deployOpenShift script to include Azure cloud provider setup for masters as part of integrated cluster setup.


# UPDATES for Origin 3.9 - May 18, 2018

1.  Adjust prep scripts and deployOpenShift script to correct NetworkManager configuration.


# UPDATES for Origin 3.9 - May 5, 2018

1.  Support configuration for 1 Master as well as 1 Infra
2.  Include playbook to test for DNS name resolution - accomodate for Azure network latency during deployment


# UPDATES for Origin 3.9 - April 28, 2018

1.  Update to deploy Origin 3.9.
2.  Deploy ASB after cluster standup.
3.  Extract playbook creation out of deployOpenShift.sh.
4.  Tighten up creation of hosts file.


# UPDATES for Origin 3.7 - February 19, 2018

1.  Add additional label to infra nodes to address TSB install.
2.  Include commands to address ASB issue after Azure Cloud Provider setup.
3.  Remove reference to Cockpit.


# UPDATES for Origin 3.7 - January 16, 2018

1.  Add support for managed and unmanaged disks.
2.  Update Azure Cloud Provider setup playbooks and configuration.
3.  Provide option to enable metrics, logging, Cockpit and Azure Cloud Provider.
4.  Include additional data disk sizes.
5.  Implement diagnostics logs for VMs.
6.  General cleanup.


# UPDATE - December 21, 2017

1.  Created branch for release-3.6.
2.  Updated git clone to branch release-3.6.


# UPDATES for Release 3.6 - September 15, 2017

1.  Removed option to select between CentOS and RHEL.  This template uses CentOS.  This can be changed by forking the repo and changing the variable named osImage in azuredeploy.json
2.  Removed installation of Azure CLI as this is no longer needed.
3.  Removed dnslabel parameters and made them variables to simplify deployment.
4.  Added new D2-64v3, D2s-64sv3, E2-64v3, and E2s-64sv3 VM types.
5.  Updated prep scripts to include additional documented pre-requisites.
6.  Removed option to install single master cluster.  Now supports 3 or 5 masters and 2 or 3 infra nodes.
7.  Configure CentOS to use NetworkManager on eth0 - Thank you to @sozercan for help with this piece!

