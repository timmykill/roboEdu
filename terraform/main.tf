variable "corso" {
  type = string
  description = "stringa corrispondente al corso"
}

variable "anno" {
  type = string
  description = "stringa corrispondente all'anno"
}

variable "id" {
  type = string
  description = "id univoco della macchina"
  default = 0
}

locals {
	nomeRoba = join("-", [var.corso, var.anno, var.id])
	nomeKey = join("-", [local.nomeRoba, "key"])
	pathKey = join("", ["../secrets/", local.nomeKey])
	nomeVps = join("-", [local.nomeRoba, "client"])
}

terraform {
	required_providers {
		hcloud = {
			source = "hetznercloud/hcloud"
			version = "1.20.1"
		}
	}
}

# Configure the Hetzner Cloud Provider
provider "hcloud" {
	token = chomp(file("../secrets/hcloud_key"))
}

#  Main ssh key
resource "hcloud_ssh_key"  "myKey" {
  name       = local.nomeKey
  public_key = file(join("", [local.pathKey, ".pub"]))
}

resource "hcloud_server" "myVps" {
  name        = local.nomeVps
  image       = "ubuntu-20.04"
  server_type = "cpx41"
  ssh_keys    = ["${hcloud_ssh_key.myKey.name}"]
}

output "teams_client_public_ipv4" {
  value = "${hcloud_server.myVps.ipv4_address}"
}
