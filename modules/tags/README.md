# tags

The one place where tags are decided. It validates the mandatory tags, merges the optional and custom tags and returns a single map that every other module takes as `tags`.

## Owns

- Mandatory tags `Environment`, `Service` and `Repository`, plus `ManagedBy = "terraform"`.
- The agreed optional set (`Owner`, `CostCentre`, `DataClassification`, `Component`) and free-form custom tags.
- Normalisation: `Environment` and `Service` are lower-cased, so resource names built from them are predictable.

## Does not own

- Any AWS resource; the module has no provider.
- Resource names. Other modules build names from their own `name` and `environment` inputs; use the `environment` and `service` outputs when you want the same normalised value.

## Usage

```hcl
module "tags" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/tags?ref=v0.5.1"

  environment = "integration"
  service     = "ordering"
  repository  = "example-org/example-infra"

  optional_tags = {
    Owner = "platform"
  }
}

module "ecr" {
  source = "..."

  name = "ordering-agent"
  tags = module.tags.all_tags
}
```

The values can be given as individual variables or as the map `mandatory_tags`; a key in the map wins. A missing mandatory tag, or a custom tag that reuses a mandatory or optional key, fails the plan through a precondition on `all_tags`.

## Left out of the reference shape

The reference tag modules look up an account alias map to derive account type and name, carry a long list of optional keys specific to one organisation, support another cloud and read business-capability catalogues. None of that applies here. The account number is not tagged because it already appears in every ARN.

## Tests

`terraform test` (no provider, no credentials) covers normalisation, map precedence, merging, the missing-tag and key-clash preconditions and the optional key allow-list.

## Example

`examples/basic` in this directory is a complete configuration that validates without credentials.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.6 |

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| custom\_tags | Free-form tags. They cannot reuse a mandatory or optional key | `map(string)` | `{}` | no |
| environment | Deployment environment, for example integration or production. Used when mandatory\_tags has no Environment key | `string` | `""` | no |
| mandatory\_tags | Map form of the mandatory tags. Keys: Environment, Service, Repository. A key set here wins over the matching individual variable | `map(string)` | `{}` | no |
| optional\_tags | Tags from the agreed optional set: Owner, CostCentre, DataClassification, Component | `map(string)` | `{}` | no |
| repository | Repository that owns the Terraform code. Used when mandatory\_tags has no Repository key | `string` | `""` | no |
| service | Name of the service the resources belong to. Used when mandatory\_tags has no Service key | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| all\_tags | Mandatory, optional and custom tags merged. Pass it to the tags input of every other module |
| custom\_tags | The custom tags as given |
| environment | Lower-case environment, for naming resources |
| mandatory\_tags | Environment, Service, Repository and ManagedBy |
| optional\_tags | The optional tags as given |
| repository | Repository that owns the code |
| service | Lower-case service name, for naming resources |
<!-- END_TF_DOCS -->