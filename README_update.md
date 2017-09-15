This README_update.md file will contain the update log for the latest set of updates to the templates

# UPDATES for Release 3.6

1.  Removed option to select between CentOS and RHEL.  This template uses CentOS.  This can be changed by forking the repo and changing the variable named osImage in azuredeploy.json
2.  Removed installation of Azure CLI as this is no longer needed.
3.  Removed dnslabel parameters and made them variables to simplify deployment.
4.  Added new D2-64v3, D2s-64sv3, E2-64v3, and E2s-64sv3 VM types.
5.  Updated prep scripts to include additional documented pre-requisites.
6.  Removed option to install single master cluster.  Now supports 2 or 3 masters and 2 or 3 infra nodes.
7.  Configure CentOS to use NetworkManager on eth0 - Thank you to @sozercan for help with this piece!

