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

  # "rhel10-64" also works if your Workstation version lists Red Hat Enterprise Linux 10
  guest_os_type = "rhel9-64"
  disk_size     = var.disk_size_mb
  memory        = var.memory_mb
  cpus          = var.cpus

  # VMware's paravirtual NIC; Rocky names it ens160
  network_adapter_type = "vmxnet3"

  http_directory = "http"

  # Edits the installer's GRUB entry to point it at the kickstart file. <up> moves off the default
  # "Test this media & install" entry. The menu and timing can vary by ISO, so watch the console on the first build.
  boot_command = [
    "<up><wait>e<wait>",
    "<down><down><end>",
    " inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg",
    "<leftCtrlOn>x<leftCtrlOff>"
  ]
  boot_wait = "5s"

  ssh_username         = "anb"
  ssh_private_key_file = var.ssh_private_key_path
  ssh_timeout          = "30m"

  shutdown_command = "sudo shutdown -P now"
}

build {
  sources = ["source.vmware-iso.quantaid_base"]

  # Every VM is a full clone of this image, so drop the SSH host keys and machine ID;
  # each clone generates its own on first boot
  provisioner "shell" {
    inline = [
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo truncate -s 0 /etc/machine-id",
    ]
  }
}
