# Walkthrough — Terraform Azure VM

A step-by-step guide to provisioning a Linux VM on Azure using Terraform. This covers everything from installing the tools to SSHing into a running VM with Nginx served over a public IP.

---

## Stack

- Terraform
- Azure CLI
- Azure (West US 3)
- Ubuntu 22.04 LTS
- Nginx

---

## Step 1 — Install Azure CLI

```powershell
choco install azure-cli
```

After install, refresh your shell environment:

```powershell
refreshenv
```

Verify it worked:

```bash
az --version
```

---

## Step 2 — Login to Azure

```bash
az login --use-device-code
```

Copy the URL shown, paste it in your browser, enter the code, and select your account. Once authenticated your subscription details print to the terminal.

---

## Step 3 — Create the Project Folder

```bash
mkdir terraform-azure-vm
cd terraform-azure-vm
code .
```

Create your main config file:

```bash
touch main.tf
touch userdata.sh
```

---

## Step 4 — Configure the Azure Provider

Add to `main.tf`:

```hcl
provider "azurerm" {
  features {}
}
```

This tells Terraform to use the Azure Resource Manager provider. It authenticates using your active `az login` session.

---

## Step 5 — Create the Resource Group

```hcl
resource "azurerm_resource_group" "azure-rg" {
  name     = "terraform-azure"
  location = "West US 3"
}
```

Everything you build lives inside this resource group. Think of it as a folder in Azure.

---

## Step 6 — Create the Virtual Network

```hcl
resource "azurerm_virtual_network" "azure-vnet" {
  name                = "terraform-vnet"
  resource_group_name = azurerm_resource_group.azure-rg.name
  location            = azurerm_resource_group.azure-rg.location
  address_space       = ["10.0.0.0/16"]
}
```

Defines the private network your VM lives in. The `/16` gives you a large address space to carve subnets from.

---

## Step 7 — Create the Subnet

```hcl
resource "azurerm_subnet" "azure-subnet" {
  name                 = "terraform-subnet"
  resource_group_name  = azurerm_resource_group.azure-rg.name
  virtual_network_name = azurerm_virtual_network.azure-vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}
```

A subnet carved from the VNet. The `/24` gives you 254 usable IPs. Your VM's private IP comes from this range.

---

## Step 8 — Fetch Your Public IP Dynamically

Add this data block so Terraform always picks up your current IP at plan time:

```hcl
data "http" "my_ip" {
  url = "https://api.ipify.org"
}
```

This eliminates the need to manually update your SSH rule every time your IP changes.

---

## Step 9 — Create the Network Security Group

```hcl
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

  tags = {
    environment = "Production"
  }
}
```

Two rules: HTTP open to everyone, SSH locked to your IP only. The `chomp()` function strips any trailing newline from the IP response before appending `/32`.

---

## Step 10 — Associate NSG to Subnet

```hcl
resource "azurerm_subnet_network_security_group_association" "sub-net-associate" {
  subnet_id                 = azurerm_subnet.azure-subnet.id
  network_security_group_id = azurerm_network_security_group.azure-nsg.id
}
```

Without this block the NSG exists but does nothing. This attaches it to the subnet so the rules actually apply.

---

## Step 11 — Create a Public IP

```hcl
resource "azurerm_public_ip" "azure-vm-ip" {
  name                = "terraform-azure-vm"
  resource_group_name = azurerm_resource_group.azure-rg.name
  location            = azurerm_resource_group.azure-rg.location
  allocation_method   = "Static"

  tags = {
    environment = "Production"
  }
}
```

Static allocation means the IP does not change between VM restarts.

---

## Step 12 — Create the Network Interface

```hcl
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
```

The NIC connects your VM to the subnet and attaches the public IP so it's reachable from the internet.

---

## Step 13 — Generate an SSH Key

```bash
ssh-keygen -t rsa -b 4096
```

Hit Enter through all prompts. Keys save to `~/.ssh/id_rsa` (private) and `~/.ssh/id_rsa.pub` (public).

Verify:

```bash
ls ~/.ssh/
```

---

## Step 14 — Create the userdata.sh Bootstrap Script

In your project root, add `userdata.sh`:

```bash
#!/bin/bash
apt-get update -y
apt-get install -y nginx
systemctl start nginx
systemctl enable nginx
```

This runs once on first boot and installs Nginx automatically.

---

## Step 15 — Create the Linux VM

```hcl
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
```

---

## Step 16 — Output the Public IP

```hcl
output "public_ip" {
  value = azurerm_public_ip.azure-vm-ip.ip_address
}
```

After apply, Terraform prints the public IP directly to your terminal.

---

## Step 17 — Run Terraform

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

`-out=tfplan` saves the plan so what gets applied is exactly what was reviewed. Best practice, especially in pipelines.

---

## Step 18 — Verify

Paste the public IP in your browser. Nginx default page means everything worked.

SSH into the VM:

```bash
ssh -i ~/.ssh/id_rsa adminuser@<public_ip>
```

---

## Step 19 — Tear Down

```bash
terraform destroy
```

Removes everything Terraform created in Azure.

---

## Troubleshooting

### `azure` command not found after install

The shell had not picked up the new PATH yet. Run `refreshenv` in PowerShell or close and reopen the terminal. The correct command is `az`, not `azure`.

---

### Resource group already exists error

```
Error: a resource with the ID "..." already exists
```

The resource group was created manually or in a previous run. Terraform does not know about it. Import it into state:

```bash
terraform import azurerm_resource_group.azure-rg /subscriptions/<sub-id>/resourceGroups/terraform-azure
```

Then re-run `terraform apply`.

---

### NSG SSH rule invalid address prefix

```
SecurityRuleInvalidAddressPrefix: Value provided: <!DOCTYPE html>...
```

The IP fetch URL returned an HTML page instead of a plain IP. Using `https://ifconfig.me` without the `/ip` path caused this. Fix: switch to `https://api.ipify.org` which always returns a raw IP, then wrap with `chomp()` to strip any whitespace.

---

### SSH connection timed out

```
ssh: connect to host x.x.x.x port 22: Connection timed out
```

Two possible causes:

1. Your IP changed since the NSG rule was written. Run `curl ifconfig.me` and compare to the rule. Re-run `terraform plan -out=tfplan && terraform apply tfplan` to update it.
2. NSG was never associated to the subnet. Confirm the `azurerm_subnet_network_security_group_association` block exists in `main.tf`.

---

### SSH public key not injected into VM

The VM was provisioned before the SSH key existed. The key must be present before `terraform apply` runs. Destroy and recreate the VM after generating the key:

```bash
terraform destroy
terraform apply tfplan
```

---

### VM size not available in region

```
SkuNotAvailable: Standard_F2 is currently not available in West US 3
```

Not all VM sizes are available in every region. Switch to an available size. `Standard_D2s_v3` (2 vCPUs, 8 GiB RAM) worked in this region.

---

### file() path error for SSH public key

```
Invalid value for "path" parameter: no file exists at "~/.ssh/id_rsa.pub"
```

On Windows, Terraform does not always resolve the `~` shorthand correctly. Use the full absolute path instead:

```hcl
public_key = file("C:/Users/DELL/.ssh/id_rsa.pub")
```

---

## Notes

- Azure calls bootstrap scripts `custom_data`, not `user_data` like AWS
- Always use `terraform plan -out=tfplan` before applying — it locks in exactly what gets deployed
- The `chomp()` function is important when using dynamic IP fetching — it strips trailing newlines that would break the CIDR notation
- `Standard_D2s_v3` is a solid general-purpose size for dev and learning workloads
