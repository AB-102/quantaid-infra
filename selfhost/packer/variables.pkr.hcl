variable "iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/26.04/ubuntu-26.04-live-server-amd64.iso"
}

variable "iso_checksum" {
  type    = string
  default = "file:https://releases.ubuntu.com/26.04/SHA256SUMS"
}

# Pairs with the public key in http/user-data; Packer uses it to detect when the install finishes
variable "ssh_private_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519"
}

variable "output_directory" {
  type    = string
  default = "output/quantaid-base"
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
