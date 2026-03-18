# Terraform Azure VM

Provisions a Linux virtual machine on Azure with networking, security, and a bootstrapped Nginx web server. Built as part of a structured Cloud & DevOps learning path.

---
![Architecture](./docs/architecture.svg)

## What This Builds

- Resource group
- Virtual network and subnet (`10.0.0.0/16` / `10.0.1.0/24`)
- Network security group (HTTP open, SSH restricted to your IP)
- Public IP (static)
- Network interface
- Ubuntu 22.04 LTS VM (`Standard_D2s_v3`)
- Nginx installed on first boot via `custom_data`

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) installed
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed
- An active Azure subscription
- SSH key pair at `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`

---

## Project Structure

```     
terraform-azure-vm/
├── main.tf				# All resources defined here
├── userdata.sh			# Bootstrap script (installs Nginx)
├── README.md			# Quick overview, what it builds, how to run it
├── WALKTHROUGH.md		# Full step-by-step guide with troubleshooting
└── docs/
    └── architecture.png	# Diagram
```

For a detailed step-by-step breakdown of every resource, command, and error fix — see [WALKTHROUGH.md](./WALKTHROUGH.md).

---

## Setup

**1. Clone the repo**
```bash
git clone https://github.com/0dow0ri7s3/tf-azure-linux-vm.git
cd tf-azure-linux-vm.git
```

**2. Login to Azure**
```bash
az login --use-device-code
```

**3. Generate SSH key (if you don't have one)**
```bash
ssh-keygen -t rsa -b 4096
```

**4. Initialize Terraform**
```bash
terraform init
```

**5. Plan and apply**
```bash
terraform plan -out=tfplan
terraform apply tfplan
```

After apply, the public IP prints to the terminal. Paste it in a browser — Nginx default page confirms the VM is running.

---

## SSH Into the VM

```bash
ssh -i ~/.ssh/id_rsa adminuser@<public_ip>
```

---

## Dynamic IP on NSG

The SSH rule auto-fetches your current public IP at plan time using:

```hcl
data "http" "my_ip" {
  url = "https://api.ipify.org"
}
```

No manual IP updates needed. Just re-run `terraform plan -out=tfplan && terraform apply tfplan` after a restart.

---

## userdata.sh

Runs once on first boot:

```bash
#!/bin/bash
apt-get update -y
apt-get install -y nginx
systemctl start nginx
systemctl enable nginx
```

---

## Tear Down

```bash
terraform destroy
```

Removes all provisioned resources from Azure.

---

## Key Lessons

- Terraform state management and resource imports
- NSG rule scoping (HTTP public, SSH locked to one IP)
- Public IP attachment via NIC
- SSH key-based auth on Azure Linux VMs
- `custom_data` for VM bootstrapping (Azure's equivalent of AWS user data)
- Dynamic IP fetching to avoid hardcoded values in security rules

---

## Author

**Odoworitse**  
Junior DevOps Engineer  
[GitHub](https://github.com/0dow0ri7s3) · [LinkedIn](www.linkedin.com/in/odoworitse-afari)
