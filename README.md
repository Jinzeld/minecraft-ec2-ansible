# 🎮 Minecraft Server on AWS — Infrastructure as Code

Automated deployment of a Minecraft Java Edition server on AWS EC2 using **Terraform** (infrastructure) and **Ansible** (configuration). No AWS Console interaction required after initial credential setup.

---

## Background

### What are we doing?

This project fully automates the provisioning, configuration, and deployment of a Minecraft server on AWS. A few commands spin up a fresh EC2 instance, install Docker, deploy the server in a container, and configure it to auto-start on reboot — all without ever touching the AWS Management Console.

### How does it work?

The pipeline is split into two clearly separated stages:

**Stage 1 — Terraform (Infrastructure)**  
Terraform talks directly to AWS APIs to create all the cloud resources: VPC, subnet, internet gateway, route table, security group, key pair, and EC2 instance. When it finishes, it automatically writes the EC2 public IP into Ansible's inventory file so the next stage knows where to connect.

**Stage 2 — Ansible (Configuration + Deployment)**  
Ansible SSHs into the new EC2 instance and takes over from there. It installs Docker, writes a `docker-compose.yml` and a `systemd` service unit, then pulls the [`itzg/minecraft-server`](https://github.com/itzg/docker-minecraft-server) Docker image and starts everything up.

### Why this split?

Terraform is purpose-built for managing cloud infrastructure — it tracks state, handles dependencies between resources, and makes teardown trivial. Ansible is better suited for configuring what's running *inside* a server. Splitting them along that line keeps each tool doing what it's best at.

### Why Docker?

The `itzg/minecraft-server` image handles Java, all server dependencies, and version management. The `stop_grace_period` in the Compose file gives the server time to save the world before the container stops, which fixes the improper shutdown issue from Part 1. Upgrading the Minecraft version is just a variable change.

---

## Pipeline Diagram

```
Local Machine
│
├──► Step 1: terraform apply
│         terraform/
│         • Generate SSH key pair                  ──────────────►  AWS
│         • Create VPC + Subnet + IGW + Route Table               ├─ VPC / Networking
│         • Create Security Group (22, 25565)                     ├─ Security Group
│         • Launch EC2 t3.medium (Ubuntu 24.04)                   ├─ EC2 Instance
│         • Write ansible/inventory/hosts.ini  ◄── public IP ─────┘
│
└──► Step 2: ansible-playbook site.yml
          │
          ├──► [configure role]  ───────────────────────────────►  EC2 Instance
          │    • Install Docker Engine + Compose plugin             ├─ Docker installed
          │    • Create /opt/minecraft data directory               ├─ docker-compose.yml
          │    • Template docker-compose.yml                        └─ minecraft.service enabled
          │    • Template + enable systemd minecraft.service
          │
          └──► [docker role]  ──────────────────────────────────►  EC2 Instance
               • Pull itzg/minecraft-server image                  ├─ Container running
               • Start minecraft systemd service                   └─ Port 25565 open
               • Wait for port 25565 to be ready
```

---

## Requirements

### Tools

| Tool | Version | Install |
|------|---------|---------|
| Terraform | ≥ 1.6.0 | [terraform.io](https://developer.hashicorp.com/terraform/install) |
| Ansible | ≥ 2.15 | `pip install ansible` |
| Python | ≥ 3.10 | [python.org](https://www.python.org/) |
| AWS CLI | ≥ 2.x | [AWS CLI install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| nmap | any | `brew install nmap` / `apt install nmap` |

### Ansible Collections

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

### AWS Credentials

This project uses AWS Academy Learner Lab credentials. You need to export them as environment variables before running anything.

1. Open your Learner Lab and click **AWS Details > AWS CLI**.
2. Copy the three credential values.
3. Export them in your terminal:

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_SESSION_TOKEN="your-session-token"
export AWS_DEFAULT_REGION="us-east-1"
```

> **Note:** Learner Lab credentials expire every few hours. If you get an auth error, re-export fresh credentials from the Learner Lab panel and re-run.

---

## Repository Structure

```
minecraft-aws-iac/
├── site.yml                              # Ansible entry point (configure + deploy)
├── ansible.cfg                           # Ansible config
├── teardown.sh                           # Destroy all AWS resources
├── .gitignore
│
├── terraform/
│   ├── main.tf                           # All AWS resources
│   ├── variables.tf                      # Input variables
│   ├── outputs.tf                        # Public IP, SSH/nmap commands
│   ├── inventory.tpl                     # Template for Ansible hosts.ini
│   └── terraform.tfvars.example          # Example variable overrides
│
└── ansible/
    ├── requirements.yml                  # Collection dependencies
    ├── group_vars/
    │   └── all.yml                       # Minecraft server variables
    ├── inventory/
    │   └── hosts.ini                     # Auto-generated by Terraform
    └── roles/
        ├── configure/
        │   ├── tasks/main.yml            # Install Docker + systemd setup
        │   └── templates/
        │       ├── docker-compose.yml.j2
        │       └── minecraft.service.j2
        └── docker/
            └── tasks/main.yml            # Pull image + start service
```

---

## Running the Pipeline

### Step 1 — Clone the repo

```bash
git clone https://github.com/<your-username>/minecraft-aws-iac.git
cd minecraft-aws-iac
```

### Step 2 — Install dependencies

```bash
pip install ansible
ansible-galaxy collection install -r ansible/requirements.yml
```

Install Terraform from [terraform.io](https://developer.hashicorp.com/terraform/install) if you haven't already.

### Step 3 — Export AWS credentials

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
export AWS_DEFAULT_REGION="us-east-1"
```

### Step 4 — Provision infrastructure with Terraform

```bash
cd terraform
terraform init
terraform apply
cd ..
```

Terraform will show a plan of everything it's going to create. Type `yes` to confirm. When it finishes (~1–2 min) it prints the public IP and auto-populates `ansible/inventory/hosts.ini`.

### Step 5 — Configure and deploy with Ansible

```bash
ansible-playbook site.yml
```

This SSHs into the instance, installs Docker, deploys the container, and starts the Minecraft service. Takes around 2–3 minutes. When it finishes, the server is live.

---

## Verify the Server is Running

Use the `nmap_command` printed by Terraform, or run:

```bash
nmap -sV -Pn -p T:25565 <PUBLIC_IP>
```

Expected output:

```
PORT      STATE SERVICE   VERSION
25565/tcp open  minecraft Minecraft 1.21.x (Protocol: ...)
```

To connect in-game, open Minecraft Java Edition → **Multiplayer > Add Server** → enter the public IP.

---

## Auto-Start and Graceful Shutdown

The `minecraft` systemd service is configured to:

- **Auto-start** on boot via `systemctl enable`
- **Stop gracefully** — `ExecStop` sends `rcon-cli stop` to the server before docker compose tears down the container, giving the world time to save (fixes the improper shutdown bug from Part 1)
- **Auto-restart** on failure via `Restart=on-failure`

---

## Teardown

When you're done, run this from the project root to destroy all AWS resources:

```bash
bash teardown.sh
```

It prompts for confirmation before deleting anything.

---

## Resources & Sources

- [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) — Docker image used for the server
- [Terraform AWS Provider docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Ansible community.docker collection](https://docs.ansible.com/ansible/latest/collections/community/docker/)
- [AWS EC2 documentation](https://docs.aws.amazon.com/ec2/)
- [systemd service units](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [Docker Compose reference](https://docs.docker.com/compose/compose-file/)
