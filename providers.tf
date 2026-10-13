terraform {
  # Resource conditions (precondition blocks) need Terraform 1.2 or later. Resource Manager runs up
  # to 1.5.x: choose 1.5.x, or at least 1.2.x, when you create the stack.
  required_version = ">= 1.2.0"
}

provider "oci" {}
