# React App VM — Azure

Deploys a React application on an Azure Linux VM using Terraform. The entire setup — infrastructure, dependencies, build, and deployment — is fully automated. No manual steps after `terraform apply`.

---

![Architecture](./docs/reareact-app-vm.svg)

---

## What This Builds

- Resource group
- Virtual network and subnet (`10.0.0.0/16` / `10.0.1.0/24`)
- Network security group (HTTP open, SSH restricted to your IP)
- Public IP (Static, Standard SKU)
- Network interface
- Ubuntu 22.04 LTS VM (`Standard_D2s_v3`)
- Node.js, npm, Git, and Nginx installed on first boot
- React app cloned, built, and served via Nginx — all automated

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) installed
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed
- An active Azure subscription
- SSH key pair at `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`

---

## Project Structure

```
react-app-vm/
├── main.tf            # All infrastructure defined here
├── userdata.sh        # Bootstrap script — installs and deploys the React app
├── .gitignore         # Excludes Terraform state and sensitive files
├── README.md          # Quick overview and setup guide
├── WALKTHROUGH.md     # Full step-by-step guide with explanations and troubleshooting
└── docs/
    └── architecture.png
```

For a full step-by-step breakdown see [WALKTHROUGH.md](./WALKTHROUGH.md)

---

## Setup

**1. Clone the repo**
```bash
git clone https://github.com/0dow0ri7s3/tf-azure-infrastructure.git
cd tf-azure-infrastructure/react-app-vm
```

**2. Login to Azure**
```bash
az login --use-device-code
```

**3. Initialize Terraform**
```bash
terraform init
```

**4. Plan and apply**
```bash
terraform plan -out=tfplan
terraform apply tfplan
```

After apply, the public IP prints to the terminal. Wait 3 to 5 minutes for the bootstrap script to finish, then paste the IP in your browser. The React app loads automatically.

---

## Access the App

Paste the public IP in your browser:
```
http://<public_ip>
```

---

## SSH Into the VM

```bash
ssh -i ~/.ssh/id_rsa react-admin@<public_ip>
```

---

## Dynamic IP on NSG

The SSH rule auto-fetches your current public IP at plan time:

```hcl
data "http" "my_ip" {
  url = "https://api.ipify.org"
}
```

No manual IP updates needed. Re-run `terraform plan -out=tfplan && terraform apply tfplan` after a network change.

---

## What userdata.sh Does

Runs once on first boot:

```bash
apt-get update && install nginx nodejs npm git
git clone https://github.com/0dow0ri7s3/my-react-app.git
npm install && npm run build
copy build files to /var/www/html
configure nginx for React routing
restart nginx
```

---

## Tear Down

```bash
terraform destroy
```

Removes all provisioned resources from Azure.

---

## Key Lessons

- Terraform provider version locking with `required_providers`
- Standard SKU public IP required when Basic SKU quota is exhausted
- `custom_data` automates full app deployment — no SSH needed post-deploy
- `chomp()` strips trailing newlines from dynamic IP fetch before appending `/32`
- Nginx must be configured for React routing — all paths redirect to `index.html`
- `base64encode(file())` is required when passing shell scripts via `custom_data`

---

## Author

**Odoworitse Ab. Afari**
Junior DevOps Engineer
[GitHub](https://github.com/0dow0ri7s3) · [LinkedIn](https://linkedin.com/in/odoworitse-afari)
