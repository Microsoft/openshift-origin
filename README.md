# OpenShift Origin Deployment Template

## NOTE: Structural change to Repo

The master branch will now contain the most current release of OpenShift Origin with experimental items.  This may cause instability but will include new things or try new things.

Re-introduced non-HA deployment option with 1 Master node.

We now have branches for the stable releases:
- release-3.6
- release-3.7
- release-3.9
- azurestack-release-3.7
- azurestack-release-3.9
- etc.

Bookmark [aka.ms/OpenShift](http://aka.ms/OpenShift) for future reference.

For the **OpenShift Container Platform** refer to https://github.com/Microsoft/openshift-container-platform

Additional documentation for deploying OpenShift in Azure can be found here: https://docs.microsoft.com/en-us/azure/virtual-machines/linux/openshift-get-started

Change log located in CHANGELOG.md

## OpenShift Origin 3.9 with Username / Password

To view all the default templates, please select from the openshift project.

This template deploys OpenShift Origin with basic username / password for authentication to OpenShift. This uses CentOS and includes the following resources:

|Resource           |Properties                                                                                                                          |
|-------------------|------------------------------------------------------------------------------------------------------------------------------------|
|Virtual Network   		|**Address prefix:** 10.0.0.0/8<br />**Master subnet:** 10.1.0.0/16<br />**Node subnet:** 10.2.0.0/16                      |
|Master Load Balancer	|2 probes and 2 rules for TCP 443 and TCP 9090 <br/> NAT rules for SSH on Ports 2200-220X                                           |
|Infra Load Balancer	|3 probes and 3 rules for TCP 80, TCP 443 and TCP 9090 									                                             |
|Public IP Addresses	|OpenShift Master public IP attached to Master Load Balancer<br />OpenShift Router public IP attached to Infra Load Balancer            |
|Storage Accounts <br />Unmanaged Disks  	|1 Storage Account for Master VMs <br />1 Storage Account for Infra VMs<br />2 Storage Accounts for Node VMs<br />2 Storage Accounts for Diagnostics Logs <br />1 Storage Account for Private Docker Registry<br />1 Storage Account for Persistent Volumes  |
|Storage Accounts <br />Managed Disks      |2 Storage Accounts for Diagnostics Logs <br />1 Storage Account for Private Docker Registry |
|Network Security Groups|1 Network Security Group Master VMs<br />1 Network Security Group for Infra VMs<br />1 Network Security Group for Node VMs  |
|Availability Sets      |1 Availability Set for Master VMs<br />1 Availability Set for Infra VMs<br />1 Availability Set for Node VMs  |
|Virtual Machines   	|1, 3 or 5 Masters. First Master is used to run Ansible Playbook to install OpenShift<br />1, 2 or 3 Infra nodes<br />User-defined number of Nodes (1 to 30)<br />All VMs include a single attached data disk for Docker thin pool logical volume|

If you have a Red Hat subscription and would like to deploy an OpenShift Container Platform (formerly OpenShift Enterprise) cluster, please visit: https://github.com/Microsoft/openshift-container-platform

## READ the instructions in its entirety before deploying!

Additional documentation for deploying OpenShift in Azure can be found here: https://docs.microsoft.com/en-us/azure/virtual-machines/linux/openshift-get-started

This template deploys multiple VMs and requires some pre-work before you can successfully deploy the OpenShift Cluster. If you don't get the pre-work done correctly, you will most likely fail to deploy the cluster using this template.  Please read the instructions completely before you proceed.

## Prerequisites

### Generate SSH Keys

You'll need to generate a pair of SSH keys in order to provision this template. Ensure that you do **NOT** include a passphrase with the private key.

If you are using a Windows computer, you can download puttygen.exe. You will need to export to OpenSSH (from Conversions menu) to get a valid Private Key for use in the Template.

From a Linux or Mac, you can just use the ssh-keygen command. Once you are finished deploying the cluster, you can always generate new keys that uses a passphrase and replace the original ones used during inital deployment.

### Create Key Vault to store SSH Private Key

You will need to create a Key Vault to store your SSH Private Key that will then be used as part of the deployment.

1. **Create Key Vault using Powershell**<br/>
  a.  Create new resource group: New-AzureRMResourceGroup -Name 'ResourceGroupName' -Location 'West US'<br/>
  b.  Create key vault: New-AzureRmKeyVault -VaultName 'KeyVaultName' -ResourceGroup 'ResourceGroupName' -Location 'West US'<br/>
  c.  Create variable with sshPrivateKey: $securesecret = ConvertTo-SecureString -String '[copy ssh Private Key here - including line feeds]' -AsPlainText -Force<br/>
  d.  Create Secret: Set-AzureKeyVaultSecret -Name 'SecretName' -SecretValue $securesecret -VaultName 'KeyVaultName'<br/>
  e.  Enable the Key Vault for Template Deployments: Set-AzureRmKeyVaultAccessPolicy -VaultName 'KeyVaultName' -ResourceGroupName 'ResourceGroupName' -EnabledForTemplateDeployment

2. **Create Key Vault using Azure CLI 2.0**<br/>
  a.  Create new Resource Group: az group create -n \<name\> -l \<location\><br/>
         Ex: `az group create -n ResourceGroupName -l 'East US'`<br/>
  b.  Create Key Vault: az keyvault create -n \<vault-name\> -g \<resource-group\> -l \<location\> --enabled-for-template-deployment true<br/>
         Ex: `az keyvault create -n KeyVaultName -g ResourceGroupName -l 'East US' --enabled-for-template-deployment true`<br/>
  c.  Create Secret: az keyvault secret set --vault-name \<vault-name\> -n \<secret-name\> --file \<private-key-file-name\><br/>
         Ex: `az keyvault secret set --vault-name KeyVaultName -n SecretName --file ~/.ssh/id_rsa`<br/>

### Generate Azure Active Directory (AAD) Service Principal

To configure Azure as the Cloud Provider for OpenShift Container Platform, you will need to create an Azure Active Directory Service Principal.  The easiest way to perform this task is via the Azure CLI.  Below are the steps for doing this.

Assigning permissions to the entire Subscription is the easiest method but does give the Service Principal permissions to all resources in the Subscription.  Assigning permissions to only the Resource Group is the most secure as the Service Principal is restricted to only that one Resource Group. 
   
**Azure CLI 2.0**

1. **Create Service Principal and assign permissions to Subscription**<br/>
  a.  az ad sp create-for-rbac -n \<friendly name\> --password \<password\> --role contributor --scopes /subscriptions/\<subscription_id\><br/>
      Ex: `az ad sp create-for-rbac -n openshiftcloudprovider --password Pass@word1 --role contributor --scopes /subscriptions/555a123b-1234-5ccc-defgh-6789abcdef01`<br/>

2. **Create Service Principal and assign permissions to Resource Group**<br/>
  a.  If you use this option, you must have created the Resource Group first.  Be sure you don't create any resources in this Resource Group before deploying the cluster.<br/>
  b.  az ad sp create-for-rbac -n \<friendly name\> --password \<password\> --role contributor --scopes /subscriptions/\<subscription_id\>/resourceGroups/\<Resource Group Name\><br/>
      Ex: `az ad sp create-for-rbac -n openshiftcloudprovider --password Pass@word1 --role contributor --scopes /subscriptions/555a123b-1234-5ccc-defgh-6789abcdef01/resourceGroups/00000test`<br/>

3. **Create Service Principal without assigning permissions to Resource Group**<br/>
  a.  If you use this option, you will need to assign permissions to either the Subscription or the newly created Resource Group shortly after you initiate the deployment of the cluster or the post installation scripts will fail when configuring Azure as the Cloud Provider.<br/>
  b.  az ad sp create-for-rbac -n \<friendly name\> --password \<password\> --role contributor --skip-assignment<br/>
      Ex: `az ad sp create-for-rbac -n openshiftcloudprovider --password Pass@word1 --role contributor --skip-assignment`<br/>

You will get an output similar to:

```javascript
{
  "appId": "2c8c6a58-44ac-452e-95d8-a790f6ade583",
  "displayName": "openshiftcloudprovider",
  "name": "http://openshiftcloudprovider",
  "password": "Pass@word1",
  "tenant": "12a345bc-1234-dddd-12ab-34cdef56ab78"
}
```

The appId is used for the aadClientId parameter.

### azuredeploy.Parameters.json File Explained

| Property                          | Description                                                                                                                                                                                                                                                                                                                                          | Valid options                                                                        | Default value |
|-----------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------|---------------|
`_artifactsLocation`| The base URL where artifacts required by this template are located. If you are using your own fork of the repo and want the deployment to pick up artifacts from your fork, update this value appropriately (user and branch), for example, change from `https://raw.githubusercontent.com/Microsoft/openshift-origin/master/` to `https://raw.githubusercontent.com/YourUser/openshift-origin/YourBranch/`
`masterVmSize`| Size of the Master VM. Select from one of the allowed VM sizes listed in the azuredeploy.json file ||
`infraVmSize`| Size of the Infra VM. Select from one of the allowed VM sizes listed in the azuredeploy.json file ||
`nodeVmSize`| Size of the Node VM. Select from one of the allowed VM sizes listed in the azuredeploy.json file||
`storageKind`| The type of storage to be used. | - "managed"<br>- "unmanaged"|
`openshiftClusterPrefix`| Cluster Prefix used to configure hostnames for all nodes - master, infra and nodes. Between 1 and 20 characters||
`masterInstanceCount`| Number of Masters nodes to deploy||
`infraInstanceCount`| Number of infra nodes to deploy||
`nodeInstanceCount`| Number of Nodes to deploy||
`dataDiskSize`| Size of data disk to attach to nodes for Docker volume.|- 32 GB<br>- 64 GB<br>- 128 GB<br>- 256 GB<br>- 512 GB<br>- 1024 GB<br>- 2048 GB|
`adminUsername`| Admin username for both OS login and OpenShift login||
`openshiftPassword`| Password for OpenShift login||
`enableMetrics`| Enable Metrics|- "true"<br>- "false|
`enableLogging`| Enable Logging|- "true"<br>- "false|
`sshPublicKey`| Copy your SSH Public Key here||
`keyVaultResourceGroup`| The name of the Resource Group that contains the Key Vault||
`keyVaultName`| The name of the Key Vault you created||
`keyVaultSecret`| The Secret Name you used when creating the Secret (that contains the Private Key)||
`enableAzure`| Enable Azure Cloud Provider|- "true"<br>- "false|
`aadClientId`| Azure Active Directory Client ID also known as Application ID for Service Principal||
`aadClientSecret`| Azure Active Directory Client Secret for Service Principal||
`defaultSubDomainType`| This will either be nipio (if you don't have your own domain) or custom if you have your own domain that you would like to use for routing||
`defaultSubDomain`| The wildcard DNS name you would like to use for routing if you selected custom above.  If you selected nipio above, then this field will be ignored||

## Deploy Template

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMicrosoft%2Fopenshift-origin%2Fmaster%2Fazuredeploy.json" target="_blank"><img src="http://azuredeploy.net/deploybutton.png"/></a>
<a href="https://portal.azure.us/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMicrosoft%2Fopenshift-origin%2Fmaster%2Fazuredeploy.json" target="_blank"><img src="http://azuredeploy.net/AzureGov.png"/></a>

Once you have collected all of the prerequisites for the template, you can deploy the template by populating the *azuredeploy.parameters.local.json* file and executing Resource Manager deployment commands with PowerShell or the CLI.

For Azure CLI 2.0, sample commands:

```bash
az group create --name OpenShiftTestRG --location WestUS2
```
while in the folder where your local fork resides

```bash
az group deployment create --resource-group OpenShiftTestRG --template-file azuredeploy.json --parameters @azuredeploy.parameters.local.json --no-wait
```

Monitor deployment via CLI or Portal and get the console URL from outputs of successful deployment which will look something like (if using sample parameters file and "West US 2" location):

`https://me-master1.westus2.cloudapp.azure.com/console`

The cluster will use self-signed certificates. Accept the warning and proceed to the login page.

If you chose to deploy metrics and / or logging, make sure you select an appropriate VM size (i.e. the Standard_DS2_v2 is too small).  Also, the deployment will take longer as extra time is needed for the additional playbooks to run.

### NOTE

The OpenShift Ansible playbook does take a while to run when using VMs backed by Standard Storage. VMs backed by Premium Storage are faster. If you want Premimum Storage, select a DS or GS series VM.
<hr />
Be sure to follow the OpenShift instructions to create the necessary DNS entry for the OpenShift Router for access to applications.

### TROUBLESHOOTING

If you encounter an error during deployment of the cluster, please view the deployment status. The following Error Codes will help to narrow things down.

1. Exit Code 5: Unable to provision Docker Thin Pool Volume

For further troubleshooting, please SSH into your master0 node on port 2200. You will need to be root **(sudo su -)** and then navigate to the following directory: **/var/lib/waagent/custom-script/download**<br/><br/>
You should see a folder named '0' and '1'. In each of these folders, you will see two files, stderr and stdout. You can look through these files to determine where the failure occurred.

## Post-Deployment Operations

### Additional OpenShift Configuration Options

You can configure additional settings per the official [OpenShift Origin Documentation](https://docs.openshift.org/latest/welcome/index.html).

Few options you have

1. Deployment Output
  a. openshiftConsoleUrl the openshift console url<br/>
  b. openshiftMasterSsh  ssh command for master node<br/>
  c. openshiftNodeLoadBalancerFQDN node load balancer<br/>
2. Get the deployment output data
  a. portal.azure.com -> choose 'Resource groups' select your group select 'Deployments' and there the deployment 'Microsoft.Template'. As output from the deployment it contains information about the openshift console url, ssh command and load balancer url.<br/>
  b. With the Azure CLI : 
    ```bash
    az group deployment list -g <resource group name>
    ```
3. Add additional users. you can find much detail about this in the openshift.org documentation under 'Cluster Administration' and 'Managing Users'. This installation uses htpasswd as the identity provider. To add more users, ssh in to each master node and execute following command:
   ```sh
   sudo htpasswd /etc/origin/master/htpasswd user1
   ```
  now this user can login with the 'oc' CLI tool or the openshift console url
