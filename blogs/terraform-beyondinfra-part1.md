---
layout: post
post_title: Beyond Infrastructure Part 1 - Using Terraform to Manage Azure Policies
---

Terraform is a great product for managing Azure infrastructure, but did you know that you can do a lot more than just stand up IaaS and PaaS resources?
Recently I was creating a set of [Azure Policies](https://azure.microsoft.com/en-us/services/azure-policy/) that I could port across several Azure Subscriptions. For simplicities sake, we will look at a single policy definition around requiring certain tags for every resource in the subscription.
Let's see how I used Terraform to accomplish this quickly.

## Traditional Approach

In the past, if you wanted to maintain Azure Policies, you could either use the Azure Portal or ARM Templates.

The Azure Portal is a great tool, however there is too much manual intervention and chance for human error when creating and updating policies/assignments.
ARM Templates can work as well, but don't give you the flexibility to see what the difference is between your configuration before pushing a change. Also, if you want to span multiple subscriptions you would have to create your own tooling around managing the changes across all the subscriptions.

Can Terraform do this more easily?

## Azure Terraform Provider

There are two resources of interest:

- `azurerm_policy_definition` Creates the custom Policy Definition for our subscription.
- `azurerm_policy_assignment` Creates a Policy Assignment of the Policy Definition.

### Azure Policy - Audit Required Tags

Azure Tags are key to keeping track of the infrastructure in your subscription. Unless you have thoroughly planned out your tagging strategy you may find yourself in a situation where you want to start requiring a tag on all resources. Your first question should be: "How compliant is my current infrastructure for this newly required tag?" We can easily do this with an Azure Policy using the `audit` effect.

Let's take a look at what this definition would look like in Terraform.

### azurerm_policy_definition

We need to set the following parameters:

- **name:** The name of the policy, used to build the id.
- **display_name:** The display name used in the Azure Portal.
- **description:** Technically optional, but a great way to add clarity to the purpose of the policy.
- **policy_type:** Type of policy, should be set to 'Custom'.
- **mode:** The resources this policy will affect, should be set to 'All'.
- **policy_rule:** The JSON representing the Rule
- **parameters:** The JSON representing the Parameters

To get started with the obvious fields we have:

```hcl
resource "azurerm_policy_definition" "requiredTag" {
  name         = "Audit-RequiredTag-Resource"
  display_name = "Audit a Required Tag on a Resource"
  description  = "Audit all resources for a required tag"
  policy_type  = "Custom"
  mode         = "All"
  policy_rule  = "???"
  parameters   = "???"
}
```

The `policy_rule` and `parameters` must be in the form of JSON. This is not due to a design decision on the part the Terraform Provider, it is just how Azure has to interpret the policy. This can be a little convoluted, so let's use the Terraform `template_file` provider to keep things as clean as possible.

### Rule JSON

```hcl
data "template_file" "requiredTag_policy_rule" {
  template = <<POLICY_RULE
{
    "if": {
        "field": "[concat('tags[', parameters('tagName'), ']')]",
        "exists": "false"
    },
    "then": {
        "effect": "audit"
    }
}
POLICY_RULE
}
```

### Parameter JSON

```hcl
data "template_file" "requiredTag_policy_parameters" {
  template = <<PARAMETERS
{
    "tagName": {
        "type": "String",
        "metadata": {
            "displayName": "Tag Name",
            "description": "Name of the tag, such as 'environment'"
        }
    }
}
PARAMETERS
}
```

Now we can reference these via interpolation:

```hcl
resource "azurerm_policy_definition" "requiredTag" {
  ...
  policy_rule  = "${data.template_file.requiredTag_policy_rule.rendered}"
  parameters   = "${data.template_file.requiredTag_policy_parameters.rendered}"
}
```

## Apply the Definition

Now we are ready to run a `terraform plan` where we end up with something like this:

```sh
An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  + azurerm_policy_definition.requiredTag
      id:           <computed>
      description:  "Audit all resources for a required tag"
      display_name: "Audit a Required Tag on a Resource"
      mode:         "All"
      name:         "Audit-RequiredTag-Resource"
      parameters:   "{\n    \"tagName\": {\n        \"type\": \"String\",\n        \"metadata\": {\n            \"displayName\": \"Tag Name\",\n            \"description\": \"Name of the tag, such as 'environment'\"\n        }\n    }\n}\n"
      policy_rule:  "{\n    \"if\": {\n        \"field\": \"[concat('tags[', parameters('tagName'), ']')]\",\n        \"exists\": \"false\"\n    },\n    \"then\": {\n        \"effect\": \"audit\"\n    }\n}\n"
      policy_type:  "Custom"


Plan: 1 to add, 0 to change, 0 to destroy.

------------------------------------------------------------------------
```

Running a `terraform apply` creates the Policy in the Azure Subscription.
Navigating to the [Azure Portal](https://portal.azure.com) we can see the Custom Policy:

![](assets/Azure-CustomPolicy.png)

## Azure Policy Assignment

Now that we have defined a Custom Azure Policy, we need to assign it to our subscription to make use of it.

### azurerm_policy_assignment

We need to set the following parameters:

- **name:** The name of the assignment, used to build the id.
- **display_name:** The display name used in the Azure Portal.
- **description:** Technically optional, but a great way to add clarity to the purpose of the assignment.
- **policy_definition_id:** The id of the policy definition we created above
- **scope:** The scope of this assignment, here we are scoping this to the entire subscription.
- **parameters:** The JSON representing the required tag to assign to the definition

To get started with the obvious fields we have:

```hcl
resource "azurerm_policy_assignment" "requiredTag" {
  name                 = "Audit-RequiredTag-${var.requiredTag}"
  display_name         = "Assign Required Tag '${var.requiredTag}'"
  description          = "Assignment of Required Tag Policy for '${var.requiredTag}'"
  policy_definition_id = "???"
  scope                = "???"
  parameters           = "???"
}
```

> Note the use of a variable 'requiredTag' we have created to parameterize the resource creation. More on this in a bit.

### policy_definition_id

This id is simply pulled from the id output from the `azurerm_policy_definition` resource.

```hcl
resource "azurerm_policy_assignment" "requiredTag" {
  ...
  policy_definition_id = "${azurerm_policy_definition.requiredTag.id}"
  ...
}
```

### scope

We want this policy assignment to be for the entire subscription. One option here would be to pass the subscription id as a variable, however we can source the id from the active `terraform run` by using the [azurerm_subscription](https://www.terraform.io/docs/providers/azurerm/d/subscription.html) data source.

```hcl
data "azurerm_subscription" "current" {}

resource "azurerm_policy_assignment" "requiredTag" {
  ...
  scope                = "${data.azurerm_subscription.current.id}"
  ...
}
```

### parameters

The last piece we need is the parameters JSON used to assign the 'requireTag' value in the Azure Policy. Much like we did before we leverage the `template_file` provider.

```hcl
data "template_file" "requiredTag_policy_assign" {
  template = <<PARAMETERS
{
    "tagName": {
        "value": "${var.requiredTag}"
    }
}

PARAMETERS
}

resource "azurerm_policy_assignment" "requiredTag" {
  ...
  parameters           = "${data.template_file.requiredTag_policy_assign.rendered}"
}
```

## Apply the Assignment

Now we are ready to run a `terraform plan` where we end up with something like this:

```sh
An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  + azurerm_policy_assignment.policy
      id:                   <computed>
      description:          "Assignment of Required Tag Policy for 'Environment'"
      display_name:         "Assign Required Tag Environment"
      name:                 "Audit-RequiredTag-Environment"
      parameters:           "{\n    \"tagName\": {\n        \"value\": \"Environment\"\n    }\n}\n\n"
      policy_definition_id: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/providers/Microsoft.Authorization/policyDefinitions/Audit-RequiredTag-Resource"
      scope:                "/subscription//subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"


Plan: 1 to add, 0 to change, 0 to destroy.
```

Running a `terraform apply` creates the Assignment in the Azure Subscription.
Navigating to the [Azure Portal](https://portal.azure.com) we can see the Assignment:

![](assets/Azure-Assignment.png)

Success!

But what if I have more than one required tag?

## Scaling with Count

One of the key factors to Terraform is the ability to easily scale. Let's modify our current implementation to handle a list of required tags.

First let's update our variable from a string to a list.

```hcl
variable "requiredTags" {
  default = [
    "Environment",
    "Owner",
    "Department",
  ]
}
```

Now we can inject a `count` parameter in the assignment resource:

```hcl
resource "azurerm_policy_assignment" "requiredTag" {
  count                = "${length(var.requiredTags)}"

  name                 = "Audit-RequiredTag-${var.requiredTags[count.index]}"
  display_name         = "Assign Required Tag '${var.requiredTags[count.index]}'"
  description          = "Assignment of Required Tag Policy for '${var.requiredTags[count.index]}'"
  ...
}
```

> Note that we use the length of the `requiredTags` variable to indicate how many times to repeat the assignment, then index into the list for the name.

### Parameters

The parameters value is a little less clean since we have to inject a different value depending on the index.

We can do this inline to the assignment without much trouble:

```hcl
resource "azurerm_policy_assignment" "requiredTag" {
  ...
  parameters = <<PARAMETERS
{
    "tagName": {
        "value": "${var.requiredTags[count.index]}"
    }
}
PARAMETERS
}
```

## Apply the Assignments

Now we are ready to run a `terraform plan` where we end up with something like this:

```sh
An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  + azurerm_policy_assignment.requiredTag[0]
      id:                   <computed>
      description:          "Assignment of Required Tag Policy for 'Environment'"
      display_name:         "Assign Required Tag 'Environment'"
      name:                 "Audit-RequiredTag-Environment"
      parameters:           "{\n    \"tagName\": {\n        \"value\": \"Environment\"\n    }\n}\n\n"
      policy_definition_id: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/providers/Microsoft.Authorization/policyDefinitions/Audit-RequiredTag-Resource"
      scope:                "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

  + azurerm_policy_assignment.requiredTag[1]
      id:                   <computed>
      description:          "Assignment of Required Tag Policy for 'Owner'"
      display_name:         "Assign Required Tag 'Owner'"
      name:                 "Audit-RequiredTag-Owner"
      parameters:           "{\n    \"tagName\": {\n        \"value\": \"Owner\"\n    }\n}\n\n"
      policy_definition_id: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/providers/Microsoft.Authorization/policyDefinitions/Audit-RequiredTag-Resource"
      scope:                "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

  + azurerm_policy_assignment.requiredTag[2]
      id:                   <computed>
      description:          "Assignment of Required Tag Policy for 'Department'"
      display_name:         "Assign Required Tag 'Department'"
      name:                 "Audit-RequiredTag-Department"
      parameters:           "{\n    \"tagName\": {\n        \"value\": \"Department\"\n    }\n}\n\n"
      policy_definition_id: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/providers/Microsoft.Authorization/policyDefinitions/Audit-RequiredTag-Resource"
      scope:                "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"


Plan: 3 to add, 0 to change, 0 to destroy.

------------------------------------------------------------------------
```

Notice that the tag values are are correctly indexed and displayed.

Running a `terraform apply` creates the Assignment in the Azure Subscription.
Navigating to the [Azure Portal](https://portal.azure.com) we can see the Assignments:

![](assets/Azure-Assignment-Count.png)

## Viewing Results

Once the Audit Policy Assignments have had some time to be checked, any non-compliant resources will show up in the Portal.

![](assets/Azure-Assignment-Compliance.png)

As you can see here I have several resources that do not have the "Owner" tag and I can work towards making them compliant.

Once I have a good handle on these required tags I can update the Terraform from `"effect": "audit"` to `"effect": "deny"`, this will deny any new request to create or modify any resource that doesn't have the "Owner" tag.

## Conclusions

In this post you have been shown how you can leverage Terraform to manage Azure Policies to create a consistent governance compliance across your Azure Subscription. One really great benefit to this solution is that it can be applied to many different Azure Subscriptions without much change in the configuration.

> Stay tuned for the next blog in the "Beyond Infrastructure" series!

All assets in this blog post can be found in the following [Gist](https://gist.github.com/straubt1/6f7b8056390a3843beb2e0197193af7f)


## Next Steps

To learn more about the benefits of Infrastructure as Code using Terraform, contact us at [info@cardinalsolutions.com](mailto:info@cardinalsolutions.com). From our 1-day hands-on workshop, to a 1-week guided pilot, we can help your organization implement or migrate to an Infrastructure as Code architecture for managing your cloud infrastructure.
