terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.30.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "=4.0.4"
    }
  }
}

resource "tls_private_key" "admin_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "k8s" {
  name     = "kubernetes-test"
  location = "West Europe"
  tags = {
    "terraform" = "true"
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "kubernetes-network"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.k8s.location
  resource_group_name = azurerm_resource_group.k8s.name
}

resource "azurerm_subnet" "k8sNet" {
  name                 = "kubernetes-instances"
  resource_group_name  = azurerm_resource_group.k8s.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_public_ip" "pubip" {
  count               = 3
  name                = "kubernets-publicip-${count.index}"
  location            = azurerm_resource_group.k8s.location
  resource_group_name = azurerm_resource_group.k8s.name
  allocation_method   = "Dynamic"
}

resource "azurerm_network_security_group" "k8s_sg" {
  name                = "kubernetes-network-sg"
  location            = azurerm_resource_group.k8s.location
  resource_group_name = azurerm_resource_group.k8s.name
}

resource "azurerm_network_security_rule" "allow_ssh" {
  name                       = "SSH"
  priority                   = 1002
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "22"
  source_address_prefix      = "*"
  destination_address_prefix = "*"

  resource_group_name         = azurerm_resource_group.k8s.name
  network_security_group_name = azurerm_network_security_group.k8s_sg.name
}

resource "azurerm_network_security_rule" "allow_http" {
  name                       = "HTTP"
  priority                   = 1001
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "80"
  source_address_prefix      = "*"
  destination_address_prefix = "*"

  resource_group_name         = azurerm_resource_group.k8s.name
  network_security_group_name = azurerm_network_security_group.k8s_sg.name
}

resource "azurerm_network_security_rule" "allow_k3s_api" {
  name                       = "KubernetesAPI"
  priority                   = 1003
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "6443"
  source_address_prefix      = "*"
  destination_address_prefix = "*"

  resource_group_name         = azurerm_resource_group.k8s.name
  network_security_group_name = azurerm_network_security_group.k8s_sg.name
}

resource "azurerm_network_interface" "nic" {
  count               = 3
  name                = "kubernetes-nic-${count.index}"
  location            = azurerm_resource_group.k8s.location
  resource_group_name = azurerm_resource_group.k8s.name

  ip_configuration {
    name                          = "k8s-nic-configuration"
    subnet_id                     = azurerm_subnet.k8sNet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = element(azurerm_public_ip.pubip.*.id, count.index)
  }
}

resource "azurerm_network_interface_security_group_association" "nic-sg" {
  count                     = 3
  network_interface_id      = element(azurerm_network_interface.nic.*.id, count.index)
  network_security_group_id = azurerm_network_security_group.k8s_sg.id
}

resource "azurerm_linux_virtual_machine" "node" {
  count                 = 3
  name                  = "kubernetes-instance-${count.index}"
  location              = azurerm_resource_group.k8s.location
  resource_group_name   = azurerm_resource_group.k8s.name
  network_interface_ids = [element(azurerm_network_interface.nic.*.id, count.index)]
  size                  = "Standard_B1s"

  os_disk {
    name                 = "osDisk-${count.index}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal-daily"
    sku       = "20_04-daily-lts-gen2"
    version   = "latest"
  }

  computer_name                   = "kubernetes-instance-${count.index}"
  admin_username                  = "azure"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azure"
    public_key = tls_private_key.admin_key.public_key_openssh
  }
}

output "admin_private_key" {
  value     = tls_private_key.admin_key.private_key_pem
  sensitive = true
}

output "ips" {
  value = azurerm_public_ip.pubip[*].ip_address
}