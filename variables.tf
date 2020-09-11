variable "azure_resource_group" {
  type = string
  description = "Name of the resource group to create"
  default = "calicotest"
}

variable "output_primary_keypath" {
  type = string
  description = "Path where to store the private key for SSH access to primary node"
  default = "output/primary_pk"
}