# Rocky 10 needs an x86-64-v3 CPU. On an older one, use Rocky 9: the same two URLs with /pub/rocky/9/
# and Rocky-9-latest-x86_64-minimal.iso
variable "iso_url" {
  type    = string
  default = "https://download.rockylinux.org/pub/rocky/10/isos/x86_64/Rocky-10-latest-x86_64-minimal.iso"
}

variable "iso_checksum" {
  type    = string
  default = "file:https://download.rockylinux.org/pub/rocky/10/isos/x86_64/CHECKSUM"
}

# Pairs with the public key in http/ks.cfg; Packer uses it to detect when the install finishes
variable "ssh_private_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519"
}

# Where scripts/new-vm.ps1 looks for the base image
variable "output_directory" {
  type    = string
  default = "${env("USERPROFILE")}/vmware/quantaid-base"
}

variable "vm_name" {
  type    = string
  default = "quantaid-base"
}

variable "headless" {
  type    = bool
  default = false
}

variable "disk_size_mb" {
  type    = number
  default = 20480
}

variable "memory_mb" {
  type    = number
  default = 2048
}

variable "cpus" {
  type    = number
  default = 2
}
