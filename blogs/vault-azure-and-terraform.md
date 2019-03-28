---
layout: post
post_title: Azure Vault Terraform
---

A common challenge when automating Azure Cloud Infrastructure is securely authenticating to Azure when running Terraform, specifically in automation. Typically a Service Principal is used, but it can be difficult to store securely and rotate easily. In this blog we will look at how we can leverage Hashicorp Vault and its [Secrets Engine for Azure](https://www.vaultproject.io/docs/secrets/azure/index.html) to dynamically generate and revoke Service Principals in Azure.

## Start Vault

First things first, we need a running Vault server. This can easily be done by downloading and running the Vault binary. For the sake of this blog we will run in `-dev` mode which will give us a Vault instance that will be running and unsealed.

```sh
$ vault server -dev
==> Vault server configuration:

             Api Address: http://127.0.0.1:8200
                     Cgo: disabled
         Cluster Address: https://127.0.0.1:8201
              Listener 1: tcp (addr: "127.0.0.1:8200", cluster address: "127.0.0.1:8201", max_request_duration: "1m30s", max_request_size: "33554432", tls: "disabled")
               Log Level: (not set)
                   Mlock: supported: false, enabled: false
                 Storage: inmem
                 Version: Vault v1.1.0

WARNING! dev mode is enabled! In this mode, Vault runs entirely in-memory
and starts unsealed with a single unseal key. The root token is already
authenticated to the CLI, so you can immediately begin using Vault.

You may need to set the following environment variable:

    $ export VAULT_ADDR='http://127.0.0.1:8200'

The unseal key and root token are displayed below in case you want to
seal/unseal the Vault or re-authenticate.

Unseal Key: nFMylmer6TepJCrhco9v6W9o1blXec+QiSJS97+LsZ4=
Root Token: s.nJIHtyEThymWHFQrEccJJO9e

Development mode should NOT be used in production installations!

==> Vault server started! Log data will stream in below:
```

A few important environment variables that we need to set:

```sh
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN="<Your Token From Above>"
```

We can verify all is well by running a `status` command:

```sh
$ vault status
Key             Value
---             -----
Seal Type       shamir
Initialized     true
Sealed          false
Total Shares    1
Threshold       1
Version         1.1.0
Cluster Name    vault-cluster-bb0bb0ef
Cluster ID      b989d9eb-d31a-09ec-7b06-e31752dbdec3
HA Enabled      false
```

## Create a Vault Service Principal

In order for Vault to have permissions to dynamically generate Service Principals, it needs a Service Principal of its own. We will call this the "Vault Service Principal".
The Azure CLI makes this really easy, however there are additional steps.

Create the Service Principal and give it scope over your subscription in one command:

```sh
$ az ad sp create-for-rbac -n Vault.SPN --role Owner --scope /subscriptions/<Subscription Id>
{
  "appId": "xxxx",
  "displayName": "Vault.SPN",
  "name": "http://Vault.SPN",
  "password": "xxxx",
  "tenant": "xxxx"
}
```

Now is the tricky part depending on the permissions you have in your tenant.

1. Navigate to the [Azure Portal](https://portal.azure.com)
2. Click on search at the top right and search for "App Registrations"
3. Change the filter to "All apps"
4. Search for the app name (Vault.SPN in the above example), and click on it
5. Click on "Settings -> Required Permissions -> Add -> Select API -> Windows Azure Active Directory"
6. Click on "Windows Azure Active Directory" and check the permissions:
  - Read and Write directory data
  - Read and Write all applications
7. Click on Save
8. Click on "Grant Permissions"

Once this is complete, your Vault Service Principal is ready to be used.

## Configure Vault

Configuring Vault to use the [Secrets Engine for Azure](https://www.vaultproject.io/docs/secrets/azure/index.html) using the Vault Service Principal.

For ease of demonstration, set the following environment variables with their appropriate values:

```sh
export ARM_TENANT_ID=""
export ARM_SUBSCRIPTION_ID=""
export ARM_CLIENT_ID=""
export ARM_CLIENT_SECRET=""
```

Enable the mount with a few optional parameters:

```sh
$ vault secrets enable \
  -path=azure \
  -description="Dynamic Service Principal Creation in Azure!" \
  -max-lease-ttl=1h \
  -default-lease-ttl=1h \
  azure

Success! Enabled the azure secrets engine at: azure/
```

Now that we have the secret engine enabled we need to configure it, specifically with the Vault Service Principal that will be used to grant Vault the ability to generate dynamic Service Principals.

```sh
$ vault write azure/config \
  tenant_id="${ARM_TENANT_ID}" \
  subscription_id="${ARM_SUBSCRIPTION_ID}" \
  client_id="${ARM_CLIENT_ID}" \
  client_secret="${ARM_CLIENT_SECRET}"

Success! Data written to: azure/config
```

The final step is to create a few roles that will give us varying levels of control of our subscription; one for read only, the other that allows writes.

```sh
$ vault write azure/roles/reader ttl=1h \
  azure_roles=-<<EOF
  [
    {
      "role_name": "Reader",
      "scope":  "/subscriptions/${ARM_SUBSCRIPTION_ID}"
    }
  ]
EOF

Success! Data written to: azure/roles/reader

vault write azure/roles/contributor ttl=1h \
  azure_roles=-<<EOF
  [
    {
      "role_name": "Contributor",
      "scope":  "/subscriptions/${ARM_SUBSCRIPTION_ID}"
    }
  ]
EOF

Success! Data written to: azure/roles/contributor
```

## Working with Terraform

Before we create a Service Principal, let's query Azure to see what currently exists.
Using the `az cli` query syntax, we can get all Service Principals with the prefix of "vault-". This is what the Secrets Engine will create. We haven't requested any new Service Principals yet, so we don't expect to have any results returned from the query.

> This also assumes that you do not have any other Service Principals in your organization the prefix with "vault-"

```sh
# Login to the Azure CLI
$ az login --service-principal -u ${vault_client_id} -p ${vault_client_secret} --tenant ${vault_tenant_id}

CloudName    IsDefault    Name                             State    TenantId
-----------  -----------  -------------------------------  -------  ------------------------------------
AzureCloud   True         SubscriptionName                 Enabled  TenantId

# Query for any Service Principals starting with "vault-", the prefix used by the secrets engine
$ az ad app list --query "[?starts_with(displayName, 'vault-')].{Name:displayName,Id:appId}" --all -o table

<no results to list>
```

As we can see, there are no Service Principals yet. Let's create one now! This can be done by calling the HTTP API directly or you can use the Vault cli:

```sh
$ vault read azure/creds/reader
Key                Value
---                -----
lease_id           azure/creds/reader/8vIL9Dacb43ssiTMdoQHaieZ
lease_duration     1h
lease_renewable    true
client_id          <Dynamic ID>
client_secret      <Dynamic SECRET>
```

If we re-query Azure again, we will see our dynamically created Service Principal:

```sh
$ az ad app list --query "[?starts_with(displayName, 'vault-')].{Name:displayName,Id:appId}" --all
Name                                        Id
------------------------------------------  ------------------------------------
vault-f208cff2-4afd-d269-6652-8e366c7086bb  <Dynamic ID>
```

We can also verify the scope:

```sh
$ az role assignment list --query "[].{RoleName:roleDefinitionName,Scope:scope}" --assignee <Dynamic ID>
RoleName    Scope
----------  ---------------------------------------------------
Reader      /subscriptions/<Subscription Id>
```

Let's try again but for the contributor role:

```sh
$ vault read azure/creds/contributor
Key                Value
---                -----
lease_id           azure/creds/contributor/YqvwY3cIYaBO9H26UF9tQvBW
lease_duration     1h
lease_renewable    true
client_id          <Dynamic ID>
client_secret      <Dynamic SECRET>

$ az role assignment list --query "[].{RoleName:roleDefinitionName,Scope:scope}" --assignee <Dynamic ID>
RoleName     Scope
-----------  ---------------------------------------------------
Contributor  /subscriptions/<Subscription Id>
```

```sh
$ vault lease revoke -prefix azure/creds/
All revocation operations queued successfully!
```

Querying the `az cli` again we will see that all Service Principals are now gone.

Now that we have seen how the core functionality works with Vault and Azure, let's use it to authenticate for Terraform.

## Terraform

A common solution found in automation that runs Terraform to manage Azure infrastructure, is to set environment variables before Terraform runs.

```sh
$ export ARM_CLIENT_ID="00000000-0000-0000-0000-000000000000"
$ export ARM_CLIENT_SECRET="00000000-0000-0000-0000-000000000000"
$ export ARM_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
$ export ARM_TENANT_ID="00000000-0000-0000-0000-000000000000"
```

This is obviously a very pragmatic solution, however those "secrets" are stored somewhere, typically in our automation tooling (or worse yet in a plain text file on the build agent). This creates a scenario that can be insecure and difficult to rotate.

Enter Vault.

Let's look at a simple Terraform configuration example that creates a simple resource group:

```hcl
resource "azurerm_resource_group" "test" {
  name     = "terraform-vault-rg"
  location = "centralus"

  tags {
    environment = "Production"
  }
}
```

To authenticate to Azure we will first read a secret from Vault that will be satisfied by the same secrets engine we just tested.

### Add the Vault provider to Terraform

Notice that we are not setting any values here since the two pieces of information we need to connect to Vault are the address and token, both of which are already stored in our environment variables ($VAULT_ADDR and $VAULT_TOKEN respectively):

```hcl
provider "vault" { }
```

For more information on configuring the Vault provider in Terraform, see the [docs](https://www.terraform.io/docs/providers/vault/index.html).

Next we read the secret from Vault using the `vault_generic_secret` data source:

```hcl
data "vault_generic_secret" "azure_spn" {
  path = "azure/creds/reader"
}
```

### Add the azurerm provider to Terraform

Again, notice that we are not setting some of the values here since some of the information we need to connect to Azure (tenant and subscription ids) are already stored in our environment variables ($ARM_TENANT_ID and $ARM_SUBSCRIPTION_ID respectively).

We also use the Vault output to wire up the azurerm provider:

```hcl
provider "azurerm" {
  client_id       = "${data.vault_generic_secret.azure_spn.data.client_id}"
  client_secret   = "${data.vault_generic_secret.azure_spn.data.client_secret}"
}
```

We can now run our normal Terraform workflow:

```sh
$ terraform init

Initializing provider plugins...
- Checking for available provider plugins on https://releases.hashicorp.com...
- Downloading plugin for provider "vault" (1.6.0)...
- Downloading plugin for provider "azurerm" (1.23.0)...

...
```

```sh
$ terraform plan

data.vault_generic_secret.azure_spn: Refreshing state...

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  + azurerm_resource_group.test
      id:               <computed>
      location:         "centralus"
      name:             "terraform-vault-rg"
      tags.%:           "1"
      tags.environment: "Production"


Plan: 1 to add, 0 to change, 0 to destroy.
```

Everything looks good. What do we think will happen if we run a `terraform apply`?

Let's see...

```sh
$ terraform apply

...

* azurerm_resource_group.test: 1 error(s) occurred:

* azurerm_resource_group.test: Error creating resource group: resources.GroupsClient#CreateOrUpdate: 
Failure responding to request: 
StatusCode=403 -- Original Error: autorest/azure: Service returned an error. 
Status=403 Code="AuthorizationFailed" 
Message="The client '<UUID>' with object id '<UUID>' does not have authorization to perform action
 'Microsoft.Resources/subscriptions/resourcegroups/write' over scope '/subscriptions/<UUID>/resourcegroups/
 terraform-vault-rf'."
```

### What happened?

Taking a look at the data source from Vault, we can see the request was for the "reader" role, not "contributor". Updating this value and re-running Terraform we see success!

Update vault_generic_secret data source to the contributor path: 
````hcl
data "vault_generic_secret" "azure_spn" {
  path = "azure/creds/contributor"
}
```

Re-run the terraform apply:
```sh
$ terraform apply
data.vault_generic_secret.azure_spn: Refreshing state...

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  + azurerm_resource_group.test
      id:               <computed>
      location:         "centralus"
      name:             "terraform-vault-rg"
      tags.%:           "1"
      tags.environment: "Production"


Plan: 1 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

azurerm_resource_group.test: Creating...
  location:         "" => "centralus"
  name:             "" => "terraform-vault-rg"
  tags.%:           "" => "1"
  tags.environment: "" => "Production"
azurerm_resource_group.test: Creation complete after 1s (ID: /subscriptions/<Subscription Id>/resourceGroups/terraform-vault-rg)

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

## Pros and Cons

This approach of leveraging Vault to manage Terraform connections to Azure has some great benefits but also a few drawbacks that will determine how viable a solution this is in your automation workflow.

**Pros**

* Generating Service Principals can have granular scope by implementing several Vault roles
* Service Principal secrets are less visible
* Short-lived, revokable Service Principal management is a much better security practice
* Terraform's Vault provider makes easy work of getting secrets

**Cons**

* Service Principal creation can take from 10 seconds up to a couple minutes
* Each time `plan` OR `apply` is ran, a new Service Principal is generated
  * As of the latest release of Vault 1.1.0, [Vault Agent Caching](https://www.vaultproject.io/docs/agent/caching/index.html) would alleviate this
* The Vault Service Principal that is required needs advanced permissions in Azure Active Directory

## Conclusion

In this blog we have walked through how to dynamically generate Azure Service Principals using Hashicorp Vault. The granularity that a Vault role enables, gives us great control over who can request which type of Service Principals they can create. Furthermore, short-lived secrets limit the exposure and eliminate hard coded secrets within automation pipelines.
