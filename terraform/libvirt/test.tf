provider "libvirt" {
	uri = "qemu:///system"
}

resource "libvirt_domain" "terraform_test" {
	name = "terraform_test"
}
