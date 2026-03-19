# Walkthrough — React App VM on Azure

This guide walks you through deploying a React web application on Microsoft Azure using Terraform. Every step is explained clearly. If you have never used Terraform or Azure before, this guide will still make sense. Take it one step at a time.

---

## What Are We Building?

We are going to:
1. Create cloud infrastructure on Azure using code (Terraform)
2. Launch a virtual machine (a computer running in the cloud)
3. Automatically install everything the React app needs on that machine
4. Serve the React app through a web server so anyone can visit it in a browser

All of this happens automatically. You write the code once, run a few commands, and Terraform handles the rest.

---

## Tools You Need

| Tool | What It Does | Install Link |
|------|-------------|--------------|
| Terraform | Reads your config and builds infrastructure | https://developer.hashicorp.com/terraform/install |
| Azure CLI | Lets you log into Azure from your terminal | https://learn.microsoft.com/en-us/cli/azure/install-azure-cli |
| VS Code | Code editor to write your files | https://code.visualstudio.com |
| Git Bash | Terminal to run commands on Windows | Comes with Git |

---

## Step 1 — Create the Project Folder

Open your terminal and run:

```bash
mkdir react-app-vm
cd react-app-vm
code .
```

**What this does:**
- `mkdir react-app-vm` creates a new folder called `react-app-vm`
- `cd react-app-vm` moves you into that folder
- `code .` opens the folder in VS Code

Inside VS Code, create three files:
- `main.tf` — your infrastructure code
- `userdata.sh` — the script that sets up the VM on first boot
- `.gitignore` — tells Git which files to ignore

---

## Step 2 — Log Into Azure

Before Terraform can build anything, it needs access to your Azure account.

Run:
```bash
az login --use-device-code
```

**What happens:**
- Azure gives you a URL and a code
- Open the URL in your browser, enter the code, and select your account
- Once done, your terminal is authenticated with Azure

---

## Step 3 — Generate an SSH Key

An SSH key is like a digital key and lock. You keep the private key on your machine and the public key goes onto the VM. When you connect, Azure checks if the keys match.

If you already have one from a previous project, skip this step.

```bash
ssh-keygen -t rsa -b 4096
```

Hit Enter through all the prompts. Two files get created:
- `~/.ssh/id_rsa` — your private key (never share this)
- `~/.ssh/id_rsa.pub` — your public key (this goes to the VM)

---

## Step 4 — Write the Terraform Configuration (main.tf)

Open `main.tf` in VS Code and paste the full configuration. Here is a breakdown of every block and what it does.

---

### 4.1 — Terraform and Provider Block

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {}
}
```

**What this does:**

Think of providers like plugins. Terraform by itself does not know how to talk to Azure. The `azurerm` provider teaches it how. The `http` provider lets Terraform make web requests, which we use to fetch your IP address automatically.

`version = "~>3.0"` means use version 3.x but not version 4 or above. This prevents unexpected breaking changes if the provider updates.

`features {}` is required by Azure. It enables the provider with default settings.

---

### 4.2 — Fetch Your IP Automatically

```hcl
data "http" "my_ip" {
  url = "https://api.ipify.org"
}
```

**What this does:**

Every time you run `terraform plan`, this block sends a request to `api.ipify.org` which responds with just your current public IP address. We use this later to lock SSH access to only your machine. No manual IP updates needed.

---

### 4.3 — Resource Group

```hcl
resource "azurerm_resource_group" "rg" {
  name     = "react-app-rg"
  location = "West US 3"
}
```

**What this does:**

A resource group is a container in Azure that holds all your related resources together. Think of it like a project folder. Every Azure resource you create must belong to a resource group. We create this first because everything else goes inside it.

---

### 4.4 — Virtual Network

```hcl
resource "azurerm_virtual_network" "vnet" {
  name                = "react-app-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}
```

**What this does:**

A virtual network is a private network inside Azure. It is like your home Wi-Fi network but in the cloud. Only resources inside this network can talk to each other directly.

`10.0.0.0/16` is the IP address range for this network. The `/16` means there are 65,536 possible IP addresses available inside this network to assign to resources.

Notice `azurerm_resource_group.rg.location` — this is Terraform referencing the resource group we created above instead of hardcoding the location again. If you change the location in one place, everything updates automatically.

---

### 4.5 — Subnet

```hcl
resource "azurerm_subnet" "subnet" {
  name                 = "react-app-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}
```

**What this does:**

A subnet is a smaller section carved out of the virtual network. Think of the VNet as a whole building and the subnet as one floor. Your VM will be placed on this floor.

`10.0.1.0/24` is the IP range for this subnet. The `/24` gives you 254 usable IP addresses. Your VM gets one of these as its private IP address.

---

### 4.6 — Network Security Group

```hcl
resource "azurerm_network_security_group" "nsg" {
  name                = "react-app-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-ssh"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${chomp(data.http.my_ip.response_body)}/32"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "production"
  }
}
```

**What this does:**

A Network Security Group is a firewall. It controls what traffic is allowed in and out of your resources. Without it, Azure blocks everything by default.

**allow-http rule:**
- Opens port 80 to everyone (`*`)
- Port 80 is the standard web port. This is what allows people to visit your React app in a browser

**allow-ssh rule:**
- Opens port 22 only to your IP address
- Port 22 is SSH — the protocol used to connect to and manage Linux servers
- `${chomp(data.http.my_ip.response_body)}/32` fetches your current IP and adds `/32` which means exactly that one IP address and nothing else
- `chomp()` removes any hidden newline character that would break the IP format

**priority** means the order rules are checked. Lower number = checked first.

---

### 4.7 — NSG Association

```hcl
resource "azurerm_subnet_network_security_group_association" "nsg-assoc" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}
```

**What this does:**

Creating the NSG is not enough. You have to attach it to something. This block connects the NSG to your subnet. Without this block, the firewall rules exist but do nothing — traffic is not filtered at all.

---

### 4.8 — Public IP

```hcl
resource "azurerm_public_ip" "pip" {
  name                = "react-app-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    environment = "production"
  }
}
```

**What this does:**

This creates a public IP address so your VM can be reached from the internet. Without this, your VM only has a private IP that is only accessible within the virtual network.

`allocation_method = "Static"` means the IP address stays the same even if the VM is restarted. If you use Dynamic, the IP could change on restart.

`sku = "Standard"` — Azure has two types of public IPs: Basic and Standard. We use Standard here because the Basic quota was exhausted on this subscription in this region. Standard SKU has its own separate quota.

---

### 4.9 — Network Interface

```hcl
resource "azurerm_network_interface" "nic" {
  name                = "react-app-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}
```

**What this does:**

A Network Interface Card (NIC) is the virtual network adapter for your VM. Just like a physical computer has a network card to connect to Wi-Fi or ethernet, your VM needs a NIC to connect to the network.

This NIC connects the VM to:
- The subnet for private communication within the network
- The public IP so it can be reached from the internet

`private_ip_address_allocation = "Dynamic"` means Azure automatically assigns a private IP from the subnet range.

---

### 4.10 — Linux Virtual Machine

```hcl
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "react-app-vm"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = "Standard_D2s_v3"
  admin_username        = "react-admin"
  custom_data           = base64encode(file("userdata.sh"))

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  admin_ssh_key {
    username   = "react-admin"
    public_key = file("~/.ssh/id_rsa.pub")
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

**What this does:**

This is the actual virtual machine — the computer in the cloud that will host the React app.

Breaking down each part:

`size = "Standard_D2s_v3"` — The VM spec. 2 virtual CPUs and 8 GiB of RAM. Enough to run Node.js and build a React app.

`admin_username = "react-admin"` — The username you use when you SSH into the VM.

`custom_data = base64encode(file("userdata.sh"))` — This passes your `userdata.sh` script to the VM. Azure runs this script automatically on the very first boot. `base64encode()` converts the script into a format Azure can safely receive and decode. `file()` reads the contents of `userdata.sh` from your local machine.

`network_interface_ids` — Attaches the NIC we created, which gives the VM its network connection and public IP.

`admin_ssh_key` — Injects your public SSH key into the VM so you can connect to it securely without a password.

`os_disk` — The hard drive for the VM. `Standard_LRS` is standard locally redundant storage, the most cost-effective option for dev workloads.

`source_image_reference` — The operating system to install. `Canonical` is the company that makes Ubuntu. `22_04-lts` is Ubuntu 22.04 LTS, a stable long-term support version.

---

### 4.11 — Output

```hcl
output "public_ip" {
  value = azurerm_public_ip.pip.ip_address
}
```

**What this does:**

After Terraform finishes deploying, this prints the public IP address directly in your terminal. You use this IP to visit the React app in your browser.

---

## Step 5 — Write the userdata.sh Script

This is the script that runs automatically when the VM boots for the first time. It handles everything — installing software, cloning the app, building it, and serving it.

Create `userdata.sh` and paste this:

```bash
#!/bin/bash
apt-get update -y
apt-get install -y nginx nodejs npm git

# Clone the React app
git clone https://github.com/pravinmishraaws/my-react-app.git /home/react-admin/my-react-app
cd /home/react-admin/my-react-app

# Personalize with your name and date
sed -i 's/Your Full Name/Odoworitse Ab. Afari/g' src/App.js
sed -i 's/DD\/MM\/YYYY/19\/03\/2026/g' src/App.js

# Install dependencies and build
npm install
npm run build

# Deploy to Nginx
rm -rf /var/www/html/*
cp -r build/* /var/www/html/
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# Configure Nginx for React routing
echo 'server {
  listen 80;
  server_name _;
  root /var/www/html;
  index index.html;
  location / {
    try_files $uri /index.html;
  }
  error_page 404 /index.html;
}' > /etc/nginx/sites-available/default

systemctl restart nginx
systemctl enable nginx
```

**Breaking down each section:**

`#!/bin/bash` — Tells the system this is a bash shell script. Must be the very first line. Without it the script will not run.

`apt-get update && apt-get install nginx nodejs npm git` — Updates the package list and installs four tools: Nginx (web server), Node.js (JavaScript runtime), npm (package manager), Git (to clone the app).

`git clone ...` — Downloads the React app source code from GitHub into the VM.

`sed -i 's/Your Full Name/Odoworitse Ab. Afari/g' src/App.js` — Finds the text `Your Full Name` inside the app and replaces it with your actual name. This personalizes the app without opening any files manually.

`npm install` — Downloads all the JavaScript packages the React app depends on.

`npm run build` — Compiles the React app into a `build/` folder of static files (HTML, CSS, JavaScript) ready to be served.

`rm -rf /var/www/html/*` — Clears out the default Nginx files.

`cp -r build/* /var/www/html/` — Copies the React build files into Nginx's web directory.

`chown` and `chmod` — Sets correct file permissions so Nginx can read and serve the files.

`echo 'server {...}'` — Writes an Nginx config that handles React's client-side routing. The `try_files $uri /index.html` line is important — it makes sure all URL paths load the React app instead of throwing a 404 error.

`systemctl restart nginx && systemctl enable nginx` — Restarts Nginx to pick up the new config and enables it to start automatically on every reboot.

---

## Step 6 — Create the .gitignore

Create `.gitignore` and paste this:

```gitignore
# Terraform state
*.tfstate
*.tfstate.backup
.terraform/
.terraform.lock.hcl

# Saved plans
tfplan

# Crash logs
crash.log

# Sensitive var files
*.tfvars
*.tfvars.json
```

**Why this matters:**

Terraform state files contain sensitive information about your infrastructure including IP addresses, resource IDs, and sometimes secrets. Never push these to GitHub. This file tells Git to ignore them completely.

---

## Step 7 — Initialize Terraform

```bash
terraform init
```

**What this does:**

This is always the first Terraform command you run in a new project. It downloads the Azure and HTTP providers declared in your `terraform` block and prepares the working directory. You only need to run this once unless you add new providers.

Expected output:
```
Terraform has been successfully initialized!
```

---

## Step 8 — Validate the Configuration

```bash
terraform validate
```

**What this does:**

Checks your configuration for syntax errors before you try to deploy anything. Catches typos, missing arguments, and wrong block structures. Always run this after writing or editing your config.

Expected output:
```
Success! The configuration is valid.
```

---

## Step 9 — Plan the Deployment

```bash
terraform plan -out=tfplan
```

**What this does:**

Terraform reads your config and shows you exactly what it is going to create, change, or destroy — without actually doing anything yet. Think of it as a dry run.

`-out=tfplan` saves the plan to a file called `tfplan`. This is best practice because it locks in exactly what gets deployed. When you apply, Terraform uses this saved plan instead of recalculating, so there are no surprises.

Review the output. You should see resources being added with a `+` symbol.

---

## Step 10 — Apply the Deployment

```bash
terraform apply tfplan
```

**What this does:**

This is the actual deployment. Terraform takes the saved plan and creates all the resources in Azure. It will take about 1 to 2 minutes to provision everything.

When it finishes you will see:

```
Apply complete! Resources: X added, 0 changed, 0 destroyed.

Outputs:

public_ip = "X.X.X.X"
```

Copy that public IP address.

---

## Step 11 — Wait for the App to Load

The VM is up but the `userdata.sh` script is still running in the background — installing packages, cloning the repo, and building the app. This takes 3 to 5 minutes.

While you wait, you can monitor progress by SSHing in:

```bash
ssh -i ~/.ssh/id_rsa react-admin@<public_ip>
```

Then check the cloud-init log:

```bash
sudo tail -f /var/log/cloud-init-output.log
```

This streams the script output in real time. When you see nginx restarting and no errors, the app is ready.

---

## Step 12 — Visit the App in Your Browser

Open your browser and go to:

```
http://<public_ip>
```

You should see the React app with your name and deployment date displayed.

---

## Step 13 — Tear Down

When you are done, destroy all the resources to avoid being charged:

```bash
terraform destroy
```

Terraform will show you everything it plans to delete and ask you to confirm. Type `yes` and it removes everything cleanly.

---

## Troubleshooting

### Basic SKU public IP quota exceeded

```
IPv4BasicSkuPublicIpCountLimitReached: Cannot create more than 0 IPv4 Basic SKU
```

Free and student Azure subscriptions have a low quota for Basic SKU public IPs. Fix: add `sku = "Standard"` to the public IP resource block. Standard SKU has a separate quota.

---

### React app not loading after deploy

The userdata script takes 3 to 5 minutes to complete after the VM boots. If you visit the IP immediately after apply, Nginx may still be installing. Wait a few minutes then refresh. If it still does not load, SSH in and check:

```bash
sudo cat /var/log/cloud-init-output.log
```

Look for any error lines, especially around `npm install` or `npm run build`.

---

### SSH connection timed out

Your IP address has changed since the NSG rule was written. Check your current IP:

```bash
curl ifconfig.me
```

Then re-run:

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

Terraform fetches your new IP automatically and updates the NSG rule.

---

### Nginx default page showing instead of React app

The build files were not copied correctly or the Nginx config was not applied. SSH into the VM and check:

```bash
ls /var/www/html/
sudo nginx -t
sudo systemctl status nginx
```

If the html folder is empty, the build step failed. Check the cloud-init log for npm errors.

---

## Notes

- Azure calls bootstrap scripts `custom_data`, not `user_data` like AWS
- `base64encode()` is required — Azure expects the script encoded, not raw
- `chomp()` is required around the IP fetch — removes hidden newline that breaks CIDR notation
- Standard SKU public IPs require the NSG to be explicitly associated — it does not apply automatically
- React apps need the `try_files $uri /index.html` Nginx directive — without it, page refreshes return 404
- `terraform plan -out=tfplan` is always better than plain `terraform apply` — it locks what gets deployed
