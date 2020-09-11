terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "~> 2.26.0"
    }
    random = {
      source = "hashicorp/random"
      version = "~> 2.3.0"
    }
    tls = {
      source = "hashicorp/tls"
      version = "~> 2.2.0"
    }
    template = {
        source = "hashicorp/template"
        version = "~> 2.1.2"
    }
    local = {
        source = "hashicorp/local"
        version = "~> 1.4.0"
    }
  }
}

provider "azurerm" {
    features {}
}

# Create a resource group if it doesn't exist
resource "azurerm_resource_group" "rg" {
    name     =  var.azure_resource_group
    location = "westeurope"
}

# Create virtual network
resource "azurerm_virtual_network" "vnet" {
    name                = "myVnet"
    address_space       = ["172.16.0.0/12"]
    location            = "westeurope"
    resource_group_name = azurerm_resource_group.rg.name
}

# Create subnet
resource "azurerm_subnet" "subnet" {
    name                 = "mySubnet"
    resource_group_name  = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes       = ["172.16.1.0/24"]
}

# Create public IPs for all VMs
resource "azurerm_public_ip" "pip" {
    count = 2

    name                         = "pip${count.index}"
    location                     = "westeurope"
    resource_group_name          = azurerm_resource_group.rg.name
    allocation_method            = "Dynamic"
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "nsg" {
    name                = "nsg"
    location            = "westeurope"
    resource_group_name = azurerm_resource_group.rg.name
    
    security_rule {
        name                       = "multi"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = ["22","3389"]
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

# Create network interfaces for VMs
resource "azurerm_network_interface" "nic" {
    count = 2

    name                      = "nic${count.index}"
    location                  = "westeurope"
    resource_group_name       = azurerm_resource_group.rg.name

    ip_configuration {
        name                          = "myNicConfiguration"
        subnet_id                     = azurerm_subnet.subnet.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.pip[count.index].id
    }
}

# Connect the security group to the network interfaces
resource "azurerm_network_interface_security_group_association" "nicassoc" {
    count = 2

    network_interface_id      = azurerm_network_interface.nic[count.index].id
    network_security_group_id = azurerm_network_security_group.nsg.id
}

# Create SSH key for primary node
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits = 4096
}

# public IP of primary node
output "primary_ip" {
    value = azurerm_linux_virtual_machine.primary.public_ip_address
}

# path to private key for SSH access to primary node
output "primary_keypath" {
    value = var.output_primary_keypath
}

# store SSH private key
resource "local_file" "primary_pk" {
    content  = tls_private_key.pk.private_key_pem
    filename = var.output_primary_keypath
}

# cloud config file for primary node
data "template_file" "cloudconfig" {
  template = file("scripts/cloud-config.yml")
}

# script for provisioning windows minion node
data "template_file" "win_cluster_join" {
  template = file("scripts/win-cluster-join.ps1")
}

# cloud-init for primary node
data "template_cloudinit_config" "config" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content      = data.template_file.cloudconfig.rendered
  }
}

# Create VMs primary Kubernetes Linux Node
resource "azurerm_linux_virtual_machine" "primary" {
    name                  = "primary"
    location              = "westeurope"
    resource_group_name   = azurerm_resource_group.rg.name
    network_interface_ids = [azurerm_network_interface.nic[0].id]
    size                  = "Standard_DS2_v2"
    
    custom_data = data.template_cloudinit_config.config.rendered  # add cloud-init

    os_disk {
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    admin_username = "azadmin"
    disable_password_authentication = true
        
    admin_ssh_key {
        username       = "azadmin"
        public_key     = tls_private_key.pk.public_key_openssh
    }
}

# Provision cluster with calico networking (using script in cloud-config)
resource "azurerm_virtual_machine_extension" "cluster_provision" {
  name                 = "cluster-provision"
  virtual_machine_id   = azurerm_linux_virtual_machine.primary.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  settings = <<SETTINGS
    {
        "commandToExecute": "/tmp/setup.sh"
    }
SETTINGS
}

# generate admin password for Windows VM
resource "random_password" "windows" {
  length = 16
  special = true
}

# Create VM for Kubernetes Windows Node
resource "azurerm_windows_virtual_machine" "minion" {
    name                  = "minion"
    location              = "westeurope"
    resource_group_name   = azurerm_resource_group.rg.name
    network_interface_ids = [azurerm_network_interface.nic[1].id]
    size                  = "Standard_DS2_v2"

    custom_data = base64encode(tls_private_key.pk.private_key_pem)  # store private key to allow access to primary VM to setup calico

    os_disk {
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "MicrosoftWindowsServer"
        offer     = "WindowsServer"
        sku       = "datacenter-core-1903-with-containers-smalldisk-g2"
        version   = "18362.959.2007101755"
    }

    admin_username = "azadmin"
    admin_password = random_password.windows.result
}

# public IP of minion node
output "minion_ip" {
    value = azurerm_windows_virtual_machine.minion.public_ip_address
}

# password of minion node
output "minion_password" {
    value = random_password.windows.result
}

# Join windows node to the cluster
resource "azurerm_virtual_machine_extension" "cluster_join" {
  name                 = "cluster-join"
  virtual_machine_id   = azurerm_windows_virtual_machine.minion.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"
  depends_on = [azurerm_virtual_machine_extension.cluster_provision]

  settings = <<SETTINGS
    {
        "commandToExecute": "powershell -command \"[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(data.template_file.win_cluster_join.rendered)}')) | Out-File -filepath install.ps1\" && powershell -ExecutionPolicy Unrestricted -File install.ps1"
    }
SETTINGS
}