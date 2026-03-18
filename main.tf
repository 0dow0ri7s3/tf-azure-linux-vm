# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
}

# Create a resource group
resource "azurerm_resource_group" "azure-rg" {
  name     = "terraform-azure"
  location = "West us 3"
}

# Create a virtual network within the resource group
resource "azurerm_virtual_network" "azure-vnet" {
  name                = "terraform-vnet"
  resource_group_name = azurerm_resource_group.azure-rg.name
  location            = azurerm_resource_group.azure-rg.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "azure-subnet" {
  name                 = "terraform-subnet"
  resource_group_name  = azurerm_resource_group.azure-rg.name
  virtual_network_name = azurerm_virtual_network.azure-vnet.name
  address_prefixes     = ["10.0.1.0/24"]
   
}

resource "azurerm_network_security_group" "azure-nsg" {
  name                = "terraform-nsg"
  location            = azurerm_resource_group.azure-rg.location
  resource_group_name = azurerm_resource_group.azure-rg.name

  security_rule {
    name                       = "allowhttp"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "10.0.1.0/24"
  }

  tags = {
    environment = "Production"
  }

   security_rule {
    name                       = "allowssh"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${chomp(data.http.my_ip.response_body)}/32"
    destination_address_prefix = "10.0.1.0/24"
  }
}

data "http" "my_ip" {
  url = "https://api.ipify.org"
}

resource "azurerm_subnet_network_security_group_association" "sub-net-associate" {
  subnet_id                 = azurerm_subnet.azure-subnet.id
  network_security_group_id = azurerm_network_security_group.azure-nsg.id
}

resource "azurerm_public_ip" "azure-vm-ip" {
  name                = "terraform-azure-vm"
  resource_group_name = azurerm_resource_group.azure-rg.name
  location            = azurerm_resource_group.azure-rg.location
  allocation_method   = "Static"

  tags = {
    environment = "Production"
  }
}
resource "azurerm_network_interface" "azure-nic" {
  name                = "terraform-nic"
  location            = azurerm_resource_group.azure-rg.location
  resource_group_name = azurerm_resource_group.azure-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.azure-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.azure-vm-ip.id
  }
  
}

resource "azurerm_linux_virtual_machine" "azure-vm" {
  name                = "terrafom-azure-vm"
  resource_group_name = azurerm_resource_group.azure-rg.name
  location            = azurerm_resource_group.azure-rg.location
  size                = "Standard_D2s_v3"
  admin_username      = "adminuser"
  custom_data         = base64encode(file("userdata.sh"))
  network_interface_ids = [
    azurerm_network_interface.azure-nic.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("C:/Users/DELL/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

output "public_ip" {
  value = azurerm_public_ip.azure-vm-ip.ip_address
}

