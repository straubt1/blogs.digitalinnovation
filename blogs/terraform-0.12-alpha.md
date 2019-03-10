---
layout: post
post_title: Hashicorp Releases Terraform 0.12 Alpha Release
---

This week I was fortunate enough to join one of key technology partners Hashicorp at their annual conference HashiConf. There was plenty of great updates, product releases, and feature roadmap. By far the most exciting for me was the Alpha release of Terraform 0.12 which introduces several new configuration language features. There are too many changes to discuss here, but Hashicorp has done a great job of detailing them in a blog series https://www.hashicorp.com/blog/terraform-0-1-2-preview.

During the second day of the conference [Kristin Laemmert](https://github.com/mildwonkey), one of Hashcorp's Terraform Core Engineers, presented on some of they syntax upgrades. The one that stood out to me the most is actually a combination of "dynamic blocks" and "for expressions" mainly because it solves a very specific problem I have faced when creating Azure Virtual Machines with Managed Data Disks.

## The Ask

Let us consider a request for Terraform configuration to stand up a Virtual Machine with several data disks.

The first questions you may ask are:

1. How many data disks?
2. What size disks?

When this information is explicitly known and never changes things turn out to be easy, however if they are not known or differ by application we run into issues of repeated code.

## Version ~>0.11

Consider a Virtual Machine with three Managed Data Disks, in the current HCL syntax you would have something like this:

```hcl
resource "azurerm_virtual_machine" "myvm" {
  name                  = "myvm0"
  resource_group_name   = "my-rg"
  vm_size               = "Standard_A2_v2"
  location              = "centralus"
  network_interface_ids = ["${azurerm_network_interface.myvm.id}"]

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016 - Datacenter"
    version   = "latest"
  }

  storage_os_disk {
    name              = "myvm0-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  ="myvm0"
    admin_username ="testadmin"
    admin_password ="SuperSecretPassword"
  }

  storage_data_disk {
    name              = "datadisk0"
    lun               = 0
    disk_size_gb      = 32
    create_option     = "Empty"
    managed_disk_type = "Standard_LRS"
  }

  storage_data_disk {
    name              = "datadisk1"
    lun               = 1
    disk_size_gb      = 128
    create_option     = "Empty"
    managed_disk_type = "Standard_LRS"
  }

  storage_data_disk {
    name              = "datadisk2"
    lun               = 2
    disk_size_gb      = 64
    create_option     = "Empty"
    managed_disk_type = "Standard_LRS"
  }
}
```

As you can see, the `storage_data_disk` blocks must be explicitly declared. We certainly could abstract the disk sizes into variables, but what happens when the disks need to be different sizes? Also, if I need to add or remove data disks, I have to update my Terraform configuration rather than injecting a new variable.
What is worse, if this code lives in a module, I would be forced to replicate the VM resource several times to account for every possible configuration!

Now let's see how Terraform 0.12 can help.

## Version =0.12.0-alpha1

With some of the awesome HCL syntax changes we can accomplish our task while keeping our Terraform Configuration clean.

The first thing we need to declare is a variable to capture our data disk configuration:

```hcl
variable "data_disks" {
  default = [
    {
      lun  = 0
      size = 32
    },
    {
      lun  = 1
      size = 128
    },
    {
      lun  = 2
      size = 64
    },
  ]
}
```

Above we are declaring a variable `data_disks` that contains the information we need for three data disks. For ease of this example I am simply defaulting the values, however you can imagine this could be overridden with variable assignments.

Now let's look how we can use "dynamic blocks" and "for expressions" to generate the data disks we want.

```hcl
resource "azurerm_virtual_machine" "main" {
  name = "myvm0"

  ...Some fields omitted...

  dynamic "storage_data_disk" {
    for_each = var.data_disks

    content {
      name              = "datadisk${storage_data_disk.value.lun}"
      lun               = storage_data_disk.value.lun
      disk_size_gb      = storage_data_disk.value.size
      create_option     = "Empty"
      managed_disk_type = "Standard_LRS"
    }
  }
}
```

Looking at the `dynamic` key word, we see it is followed by the name of the resource property you wish to make dynamic.
Next the `for_each` assignment, which in our example has been set to an array since we want to generate multiple "storage_data_disk" blocks.
Then we have a `content` block that will be the template used to populate the dynamic block, the contents here will look similar to a non-dynamic block in terms of the properties set. Notice that we can use the variable `storage_data_disk` which is populated for each item in the array we set.

To make this more clear lets look at the mapping that occurs behind the scenes.

Consider just this block of HCL:

```hcl
dynamic "storage_data_disk" {
for_each = var.data_disks

content {
    name              = "datadisk${storage_data_disk.value.lun}"
    lun               = storage_data_disk.value.lun
    disk_size_gb      = storage_data_disk.value.size
    create_option     = "Empty"
    managed_disk_type = "Standard_LRS"
}
}
```

In the example above, this would translate to:

```hcl
storage_data_disk {
  name              = "datadisk0"
  lun               = 0
  disk_size_gb      = 32
  create_option     = "Empty"
  managed_disk_type = "Standard_LRS"
}
storage_data_disk {
  name              = "datadisk1"
  lun               = 1
  disk_size_gb      = 128
  create_option     = "Empty"
  managed_disk_type = "Standard_LRS"
}
storage_data_disk {
  name              = "datadisk2"
  lun               = 2
  disk_size_gb      = 64
  create_option     = "Empty"
  managed_disk_type = "Standard_LRS"
}
```

## Conclusion

We have taken a look at a pragmatic problem that the new changes in Terraform 0.12 will provide a much needed solution for.
These improvements show the commitment by Hashicorp to its community to further improve Terraform, it is really exciting how far it has come and what the future entails.

## Next Steps

Did you know Cardinal Solutions is a Hashicorp Partner?

To learn more about the benefits of Infrastructure as Code using Terraform, contact us at [info@cardinalsolutions.com](mailto:info@cardinalsolutions.com). From our 1-day hands-on workshop, to a 1-week guided pilot, we can help your organization implement or migrate to an Infrastructure as Code architecture for managing your cloud infrastructure.
