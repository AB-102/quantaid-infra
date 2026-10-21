packer {
  required_plugins {
    vmware = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/vmware"
    }
  }
}

source "vmware-iso" "quantaid_base" {
  iso_url          = var.iso_url
  iso_checksum     = var.iso_checksum
  vm_name          = var.vm_name
  output_directory = var.output_directory
  headless         = var.headless

  guest_os_type = "ubuntu-64"
  disk_size     = var.disk_size_mb
  memory        = var.memory_mb
  cpus          = var.cpus

  http_directory = "http"

  # Edits the default GRUB entry to add autoinstall. The menu and timing can vary by ISO,
  # so watch the console on the first build.
  boot_command = [
    "<esc><wait>e<wait>",
    "<down><down><down><end>",
    " autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/",
    "<f10>"
  ]
  boot_wait = "5s"

  ssh_username         = "anb"
  ssh_private_key_file = var.ssh_private_key_path
  ssh_timeout          = "30m"

  shutdown_command = "sudo shutdown -P now"
}

build {
  sources = ["source.vmware-iso.quantaid_base"]
}
