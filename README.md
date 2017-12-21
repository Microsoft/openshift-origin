# OpenShift Origin Deployment Template

Bookmark [aka.ms/OpenShift](http://aka.ms/OpenShift) for future reference.

For the **OpenShift Container Platform** refer to https://github.com/Microsoft/openshift-container-platform

Change log located in CHANGELOG.md

## OpenShift Origin with Username / Password

Current template (branch release-3.6) deploys OpenShift Origin 3.6 (1.6).

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMicrosoft%2Fopenshift-origin%2Frelease-3.6%2Fazuredeploy.json" target="_blank"><img src="http://azuredeploy.net/deploybutton.png"/></a>

This template deploys OpenShift Origin with basic username / password for authentication to OpenShift. You can select to use either CentOS or RHEL for the OS. It includes the following resources:

|Resource           |Properties                                                                                                                          |
|-------------------|------------------------------------------------------------------------------------------------------------------------------------|
|Virtual Network   		|**Address prefix:** 10.0.0.0/8<br />**Master subnet:** 10.1.0.0/16<br />**Node subnet:** 10.2.0.0/16                      |
|Master Load Balancer	|1 probe and 1 rule for TCP 8443 <br/> NAT rules for SSH on Ports 2200-220X                                           |
|Infra Load Balancer	|2 probes and 2 rules for TCP 80, and TCP 443 									                                             |
|Public IP Addresses	|OpenShift Master public IP attached to Master Load Balancer<br />OpenShift Router public IP attached to Infra Load Balancer            |
|Storage Accounts   	|1 Storage Accounts for Master VMs<br />1 Storage Accounts for Infra VMs<br />2 Storage Accounts for Node VMs<br />1 Storage Account for Private Docker Registry<br />1 Storage Account for Persistent Volume  |
|Network Security Groups|1 Network Security Group Master VMs<br />1 Network Security Group for Infra VMs<br />1 Network Security Group for Node VMs  |
|Availability Sets      |1 Availability Set for Master VMs<br />1 Availability Set for Infra VMs<br />1 Availability Set for Node VMs  |
|Virtual Machines   	|3 or 5 Masters. First Master is used to run Ansible Playbook to install OpenShift<br />2 or 3 Infra nodes<br />User-defined number of Nodes (1 to 30)<br />All VMs include a single attached data disk for Docker thin pool logical volume|

If you have a Red Hat subscription and would like to deploy an OpenShift Container Platform (formerly OpenShift Enterprise) cluster, please visit: https://github.com/Microsoft/openshift-container-platform

## READ the instructions in its entirety before deploying!

This template deploys multiple VMs and requires some pre-work before you can successfully deploy the OpenShift Cluster. If you don't get the pre-work done correctly, you will most likely fail to deploy the cluster using this template.  Please read the instructions completely before you proceed.

This template uses CentOS as the base OS Image.  If you want to use the On-Demand Red Hat Enterprise Linux image from the Azure Gallery, you will need to fork this repo and edit the azuredeploy.json file.  The variable is called osImage.
>If you use the On-Demand image, there is an hourly charge for using this image.  

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

2. **Create Key Vault using Azure CLI 1.0**<br/>
  a.  Create new Resource Group: azure group create \<name\> \<location\><br/>
         Ex: `azure group create ResourceGroupName 'East US'`<br/>
  b.  Create Key Vault: azure keyvault create -u \<vault-name\> -g \<resource-group\> -l \<location\><br/>
         Ex: `azure keyvault create -u KeyVaultName -g ResourceGroupName -l 'East US'`<br/>
  c.  Create Secret: azure keyvault secret set -u \<vault-name\> -s \<secret-name\> --file \<private-key-file-name\><br/>
         Ex: `azure keyvault secret set -u KeyVaultName -s SecretName --file ~/.ssh/id_rsa`<br/>
  d.  Enable the Keyvvault for Template Deployment: azure keyvault set-policy -u \<vault-name\> --enabled-for-template-deployment true<br/>
         Ex: `azure keyvault set-policy -u KeyVaultName --enabled-for-template-deployment true`<br/>

3. **Create Key Vault using Azure CLI 2.0**<br/>
  a.  Create new Resource Group: az group create -n \<name\> -l \<location\><br/>
         Ex: `az group create -n ResourceGroupName -l 'East US'`<br/>
  b.  Create Key Vault: az keyvault create -n \<vault-name\> -g \<resource-group\> -l \<location\> --enabled-for-template-deployment true<br/>
         Ex: `az keyvault create -n KeyVaultName -g ResourceGroupName -l 'East US' --enabled-for-template-deployment true`<br/>
  c.  Create Secret: az keyvault secret set --vault-name \<vault-name\> -n \<secret-name\> --file \<private-key-file-name\><br/>
         Ex: `az keyvault secret set --vault-name KeyVaultName -n SecretName --file ~/.ssh/id_rsa`<br/>

### Generate Azure Active Directory (AAD) Service Principal

To configure Azure as the Cloud Provider for OpenShift Origin, you will need to create an Azure Active Directory Service Principal.  The easiest way to perform this task is via the Azure CLI.  Below are the steps for doing this.

You will want to create the Resource Group that you will ultimately deploy the OpenShift cluster to prior to completing the following steps.  If you don't, then wait until you initiate the deployment of the cluster before completing **Azure CLI 1.0 Step 2**. If using **Azure CLI 2.0**, complete step 2 to create the Service Principal prior to deploying the cluster and then assign permissions based on **Azure CLI 1.0 Step 2**.

**Azure CLI 1.0**

1. **Create Service Principal**<br/>
  a.  azure ad sp create -n \<friendly name\> -p \<password\> --home-page \<URL\> --identifier-uris \<URL\><br/>
      Ex: `azure ad sp create -n openshiftcloudprovider -p Pass@word1 --home-page http://myhomepage --identifier-uris http://myhomepage`

The entries for --home-page and --identifier-uris is not important for this use case so they do not have to be valid links.
You will get an output similar to this

```
info:    Executing command ad sp create
+ Creating application openshift demo cloud provider
+ Creating service principal for application 198c4803-1236-4c3f-ad90-46e5f3b4cd2a
data:    Object Id:               00419334-174b-41e8-9b83-9b5011d8d352
data:    Display Name:            openshiftcloudprovider
data:    Service Principal Names:
data:                             198c4803-1236-4c3f-ad90-46e5f3b4cd2a
data:                             http://myhomepage
info:    ad sp create command OK
```
Save the Object Id and the GUID in the Service Principal Names section.  This GUID is the Application ID / Client ID (aadClientId parameter).  The the password you entered as part of the CLI command is the input the aadClientSecret paramter.

2. **Assign permissions to Service Principal for specific Resource Group**<br/>
  a.  Sign into the Azure Portal<br/>
  b.  Select the Resource Group you want to assign permissions to<br/>
  c.  Select Access control (IAM) from middle pane<br/>
  d.  Click Add on right pane<br/>
  e.  For Role, Select Contributor<br/>
  f.  In Select field, type the name of your Service Principal to find it<br/>
  g.  Click the Service Principal from the list and hit Save<br/>

**Azure CLI 2.0**

1. **Create Service Principal and assign permissions to Resource Group**<br/>
  a.  az ad sp create-for-rbac -n \<friendly name\> --password \<password\> --role contributor --scopes /subscriptions/\<subscription_id\>/resourceGroups/\<Resource Group Name\><br/>
      Ex: `az ad sp create-for-rbac -n openshiftcloudprovider --password Pass@word1 --role contributor --scopes /subscriptions/555a123b-1234-5ccc-defgh-6789abcdef01/resourceGroups/00000test`<br/>

2. **Create Service Principal without assigning permissions to Resource Group**<br/>
  a.  az ad sp create-for-rbac -n \<friendly name\> --password \<password\> --role contributor --skip-assignment<br/>
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

To assign permissions, please follow the instructions from Azure CLI 1.0 Step 2 above.

### azuredeploy.Parameters.json File Explained

1.  _artifactsLocation: The base URL where artifacts required by this template are located. If you are using your own fork of the repo and want the deployment to pick up artifacts from your fork, update this value appropriately (user and branch), for example, change from `https://raw.githubusercontent.com/Microsoft/openshift-origin/master/` to `https://raw.githubusercontent.com/YourUser/openshift-origin/YourBranch/`
2.  masterVmSize: Size of the Master VM. Select from one of the allowed VM sizes listed in the azuredeploy.json file
3.  infraVmSize: Size of the Infra VM. Select from one of the allowed VM sizes listed in the azuredeploy.json file
3.  nodeVmSize: Size of the Node VM. Select from one of the allowed VM sizes listed in the azuredeploy.json file
5.  openshiftClusterPrefix: Cluster Prefix used to configure hostnames for all nodes - master, infra and nodes. Between 1 and 20 characters
8.  masterInstanceCount: Number of Masters nodes to deploy
8.  infraInstanceCount: Number of infra nodes to deploy
9.  nodeInstanceCount: Number of Nodes to deploy
9.  dataDiskSize: Size of data disk to attach to nodes for Docker volume - valid sizes are 128 GB, 512 GB and 1023 GB
10. adminUsername: Admin username for both OS login and OpenShift login
11. openshiftPassword: Password for OpenShift login
12. sshPublicKey: Copy your SSH Public Key here
14. keyVaultResourceGroup: The name of the Resource Group that contains the Key Vault
15. keyVaultName: The name of the Key Vault you created
16. keyVaultSecret: The Secret Name you used when creating the Secret (that contains the Private Key)
18. aadClientId: Azure Active Directory Client ID also known as Application ID for Service Principal
18. aadClientSecret: Azure Active Directory Client Secret for Service Principal
17. defaultSubDomainType: This will either be nipio (if you don't have your own domain) or custom if you have your own domain that you would like to use for routing
18. defaultSubDomain: The wildcard DNS name you would like to use for routing if you selected custom above.  If you selected nipio above, then this field will be ignored

## Deploy Template

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

`https://me-master1.westus2.cloudapp.azure.com:8443/console`

The cluster will use self-signed certificates. Accept the warning and proceed to the login page.

### NOTE

The OpenShift Ansible playbook does take a while to run when using VMs backed by Standard Storage. VMs backed by Premium Storage are faster. If you want Premimum Storage, select a DS or GS series VM.
<hr />
Be sure to follow the OpenShift instructions to create the ncessary DNS entry for the OpenShift Router for access to applications.

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
  b. With the Azure CLI : azure group deployment list &lt;resource group name>
3. Add additional users. you can find much detail about this in the openshift.org documentation under 'Cluster Administration' and 'Managing Users'. This installation uses htpasswd as the identity provider. To add more users, ssh in to each master node and execute following command:
   ```sh
   sudo htpasswd /etc/origin/master/htpasswd user1
   ```
  now this user can login with the 'oc' CLI tool or the openshift console url
