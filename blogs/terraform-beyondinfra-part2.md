---
layout: post
post_title: Beyond Infrastructure Part 2 - Using Terraform to Manage Azure Locks
---

In part 1 of the Beyond Infrastructure series we looked at how Terraform can manage Azure Policies; in part 2 we will look at Azure Locks.

When managing an Azure Subscription, there can be several teams and processes in place that have access to modify your resources. As an administrator you want to be sure that changes to critical resources are as protected as possible from any unintended changes. Luckily Azure has a mechanism to lock down resources preventing accidental deletion or modification of desired resources. Consider important resources such as Virtual Networks, Express Routes, Databases, etc. that should never be altered without explicit intent. Azure Locks give you this functionality.

<!-- Azure Locks are useful to protect critical Azure resources from being altered accidentally. -->

## Background

Before we get to the Terraform, let's go through the basics of Azure Locks.

### Types

There are two types of Azure Locks:

* `CanNotDelete` - Resource can be modified but can **not** be deleted.
* `ReadOnly` - Resource can **not** be modified and can **not** be deleted.

> Choosing the right Lock Type depends on your situation. Using the `CanNotDelete` is a default and should be the least impactful to existing processes, but `ReadOnly` will guarantee a resource will not be altered at all.

### Parent Scope

There are a few ways to scope an Azure Lock:

* `Subscription`   - All Resource Groups and all Resources within those groups are locked.
* `Resource Group` - The Resource Group and all Resources within the group are locked.
* `Resource`       - Only the Resource is locked.

> It is best to pick the highest level of inheritance that you can for the desired effect. For example, it is easier to manage a single Lock on a Resource Group than a Lock for each Resource.

## Traditional Approach

If you wanted to maintain Azure Locks in the past, there were several options:

* Azure Portal
* ARM Templates
* Azure CLI/Powershell/REST API

The Azure Portal is a great tool, however there is too much manual intervention and chance for human error when creating and updating Locks.

ARM Templates can work as well and are in the right direction, however they don't give you the flexibility to see what changes your configuration will have on the environment without pushing the changes to the environment.

Using the Azure CLI/Powershell/REST API would require you to build your own tooling around a process to manage the Locks.

Can Terraform do this more easily?

<!-- Let's look at two different scenarios, the first will be creating locks for infrastructure that -->

## Azure Terraform Provider

Taking a look at the documentation for the Azure Terraform Provider we can see the [Management Lock Resource](https://www.terraform.io/docs/providers/azurerm/r/management_lock.html).

### azurerm_management_lock

The resource is simple enough to configure.

We need to set the following parameters:

- **name:** The name of the Lock, this will be used when building the resource Id.
- **scope:** The scope of the Lock, can be a Subscription, Resource Group, or Resource Id.
- **lock_level:** The Lock level, can be `CanNotDelete` or `ReadOnly`.
- **notes:** (optional) Notes about the Lock, can be useful to describe the business case for the specific Lock.

Now let's look at a few simple examples.

### Subscription

To prevent all resources in a Subscription from being deleted:

```hcl
resource "azurerm_management_lock" "subscription-level" {
  scope      = "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  name       = "subscription-level-cannotdelete"
  lock_level = "CanNotDelete"
  notes      = "Items can't be deleted in this subscription!"
}
```

### Resource Group

To prevent the Resource Group `app-rg` and all of it's resources from being deleted:

```hcl
resource "azurerm_management_lock" "resource-group-level" {
  scope      = "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/app-rg"
  name       = "resource-group-level-cannotdelete"
  lock_level = "CanNotDelete"
  notes      = "Items can't be deleted in this resource group!"
}
```

### Resource

To prevent an individual Storage Account `mystorageaccount99` in Resource Group `app-rg` from being deleted:

```hcl
resource "azurerm_management_lock" "resource-group-level" {
  scope      = "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/app-rg/providers/Microsoft.Storage/storageAccounts/mystorageaccount99"
  name       = "resource-level-cannotdelete"
  lock_level = "CanNotDelete"
  notes      = "Item can't be deleted!"
}
```

## Scenarios

Let's look at two common scenarios for managing Locks in Azure:

* Within existing Terraform configuration
* New Terraform configuration

### Existing Terraform Configuration

If you are already using Terraform to manage your infrastructure, creating a Lock is as easy as adding the Lock resource to your existing Terraform configuration.

Consider the example below where we are creating a Resource Group named `cardinal-rg` and adding a `ReadOnly` lock to it.

```hcl
resource "azurerm_resource_group" "main" {
  name     = "cardinal-rg"
  location = "centralus"
}

resource "azurerm_management_lock" "resource-group-level" {
  name       = "resource-group-level"
  scope      = "${azurerm_resource_group.main.id}"
  lock_level = "ReadOnly"
  notes      = "This Resource Group is Read-Only"
}
```

Running the Terraform apply:

```sh
Terraform will perform the following actions:

  + azurerm_management_lock.resource-group-level
      id:         <computed>
      lock_level: "ReadOnly"
      name:       "resource-group-level"
      notes:      "This Resource Group is Read-Only"
      scope:      "${azurerm_resource_group.main.id}"

  + azurerm_resource_group.main
      id:         <computed>
      location:   "centralus"
      name:       "cardinal-rg"
      tags.%:     <computed>


Plan: 2 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

...

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

Navigating to the Azure Portal we can see the lock has been created.

![resource-group-lock-portal](assets/resource-group-lock-portal.png)

### New Terraform Configuration

In some situations you may have existing infrastructure that was not created by Terraform, or you may choose to manage your locks separately. In either of these cases you can still use Terraform to manage the locks by the Azure Resource Id.

Consider the example below where we create the Locks based only on a list of Ids.

```hcl
locals {
  // A list of resource ids that need locks created with type 'ReadOnly'
  lock_resources_readonly = [
    "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/existing-rg1",
    "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/existing-rg2/providers/Microsoft.Storage/storageAccounts/someaccount001",
  ]

  // A list of resource ids that need locks created with type 'CanNotDelete'
  lock_resources_cannotdelete = [
    "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/existing-rg3",
    "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/existing-rg4/providers/Microsoft.Storage/storageAccounts/someaccount002",
  ]
}

resource "azurerm_management_lock" "cannotdelete" {
  count      = "${length(local.lock_resources_cannotdelete)}"
  scope      = "${local.lock_resources_cannotdelete[count.index]}"
  name       = "CanNotDelete-${count.index}"
  lock_level = "CanNotDelete"
  notes      = "'Can Not Delete' Lock to prevent resource deletion."
}

resource "azurerm_management_lock" "readonly" {
  count      = "${length(local.lock_resources_readonly)}"
  scope      = "${local.lock_resources_readonly[count.index]}"
  name       = "ReadOnly-${count.index}"
  lock_level = "ReadOnly"
  notes      = "'Read Only' Lock to prevent resource modification."
}
```

Running an apply:

```sh
Terraform will perform the following actions:

  + azurerm_management_lock.cannotdelete[0]
      id:         <computed>
      lock_level: "CanNotDelete"
      name:       "CanNotDelete-0"
      notes:      "'Can Not Delete' Lock to prevent resource deletion."
      scope:      "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/existing-rg3"

  + azurerm_management_lock.cannotdelete[1]
      id:         <computed>
      lock_level: "CanNotDelete"
      name:       "CanNotDelete-1"
      notes:      "'Can Not Delete' Lock to prevent resource deletion."
      scope:      "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/existing-rg4/providers/Microsoft.Storage/storageAccounts/someaccount002"

  + azurerm_management_lock.readonly[0]
      id:         <computed>
      lock_level: "ReadOnly"
      name:       "ReadOnly-0"
      notes:      "'Read Only' Lock to prevent resource modification."
      scope:      "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/existing-rg1"

  + azurerm_management_lock.readonly[1]
      id:         <computed>
      lock_level: "ReadOnly"
      name:       "ReadOnly-1"
      notes:      "'Read Only' Lock to prevent resource modification."
      scope:      "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/existing-rg2/providers/Microsoft.Storage/storageAccounts/someaccount001"


Plan: 4 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

...

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
```

## Conclusions

In this post we have shown how you can leverage Terraform to manage Azure Locks to protect critical resources from deletion/modification in your Azure Subscription using exist or new Terraform configuration. Leveraging the Terraform workflow results in a source code driven solution that can be change controlled, versioned, and visible to your entire organization.

> Stay tuned for the next blog in the "Beyond Infrastructure" series!

All assets in this blog post can be found in the following [Gist](https://gist.github.com/straubt1/fb65310bb105d7d50aa6d6106a4fb401)

## Next Steps

To learn more about the benefits of Infrastructure as Code using Terraform, contact us at [info@cardinalsolutions.com](mailto:info@cardinalsolutions.com). From our 1-day hands-on workshop, to a 1-week guided pilot, we can help your organization implement or migrate to an Infrastructure as Code architecture for managing your cloud infrastructure.
