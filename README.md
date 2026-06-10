# Minecraft Server on AWS — Infrastructure as Code

Automated deployment of a Minecraft Java Edition server on AWS EC2 using **Terraform** (infrastructure) and **Ansible** (configuration + deployment). No AWS Console interaction required after initial credential setup.

---

## Background

### What are we doing?

This project fully automates the provisioning, configuration, and deployment of a Minecraft server on AWS. Two commands spin up a fresh EC2 instance, install Docker, deploy the server in a container, and configure it to auto-start on reboot — all without touching the AWS Management Console.

### How does it work?

The pipeline is split into two clearly separated stages:

**Stage 1 — Terraform (Infrastructure)**
Terraform talks directly to AWS APIs to create all the cloud resources: security group, key pair, and EC2 instance. When it finishes, it automatically writes the EC2 public IP into Ansible's inventory file so the next stage knows where to connect.

**Stage 2 — Ansible (Configuration + Deployment)**
Ansible SSHs into the new EC2 instance and takes over from there. It installs Docker, writes a `docker-compose.yml` and a `systemd` service unit, then pulls the [`itzg/minecraft-server`](https://github.com/itzg/docker-minecraft-server) Docker image and starts everything up.

### Why this split?

Terraform is purpose-built for managing cloud infrastructure — it tracks state, handles resource dependencies, and makes teardown simple. Ansible is better suited for configuring what's running inside a server. Splitting them along that line keeps each tool doing what it's best at.

### Why Docker?

The `itzg/minecraft-server` image handles Java and all server dependencies out of the box. The `stop_grace_period` in the Compose file gives the server time to save the world before the container stops, which fixes the improper shutdown issue from Part 1. Upgrading Minecraft versions is just a variable change.

> **Note:** This project uses the default AWS VPC due to AWS Academy restrictions. Custom VPCs are not supported in the Learner Lab environment.

---

## Pipeline Diagram

```
Local Machine
│
├──► Step 1: terraform apply
│         terraform/
│         • Generate SSH key pair (from ~/.ssh/minecraft-key.pub)   ──►  AWS
│         • Create Security Group (ports 22, 25565)                      ├─ Security Group
│         • Launch EC2 t3.medium (Ubuntu 24.04)                          ├─ EC2 Instance
│         • Write ansible/inventory/hosts.ini  ◄─── public IP ───────────┘
│
└──► Step 2: ansible-playbook site.yml
          │
          ├──► [configure role]  ──────────────────────────────────►  EC2 Instance
          │    • Install Docker Engine + Compose plugin                  ├─ Docker installed
          │    • Create /opt/minecraft data directory                    ├─ docker-compose.yml
          │    • Template docker-compose.yml                             └─ minecraft.service enabled
          │    • Template + enable systemd minecraft.service
          │
          └──► [docker role]  ─────────────────────────────────────►  EC2 Instance
               • Pull itzg/minecraft-server image                       ├─ Container running
               • Start minecraft systemd service                        └─ Port 25565 open
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

### SSH Key

Generate a local SSH key pair before running Terraform:

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/minecraft-key -N ""
```

Terraform reads `~/.ssh/minecraft-key.pub` and uploads it to AWS automatically.

### AWS Credentials

This project uses AWS Academy Learner Lab credentials.

1. Open your Learner Lab and click **AWS Details → AWS CLI**
2. Paste the credentials into `~/.aws/credentials`:

```
[default]
aws_access_key_id=ASIA...
aws_secret_access_key=...
aws_session_token=...
```

3. Create a config file for the region:

```bash
cat > ~/.aws/config << 'EOF'
[default]
region=us-east-1
EOF
```

4. Verify credentials are working:

```bash
aws sts get-caller-identity
```

> **Note:** Learner Lab credentials expire every few hours. If you get an auth error, paste fresh credentials from the Learner Lab panel and re-run.

---

## Repository Structure

```
minecraft-aws-iac/
├── site.yml                              # Ansible entry point (configure + deploy)
├── ansible.cfg                           # Ansible config
├── teardown.sh                           # Destroy all AWS resources
├── .gitignore
│
├── group_vars/
│   └── all.yml                           # Minecraft server variables
│
├── terraform/
│   ├── main.tf                           # All AWS resources + inventory generation
│   ├── outputs.tf                        # Instance ID and nmap command
│   └── inventory.tpl                     # Template for Ansible hosts.ini
│
└── ansible/
    ├── requirements.yml                  # Collection dependencies
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

### Step 3 — Generate SSH key

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/minecraft-key -N ""
```

### Step 4 — Set up AWS credentials

Paste fresh credentials from the Learner Lab into `~/.aws/credentials` and make sure `~/.aws/config` has `region=us-east-1`.

### Step 5 — Provision infrastructure with Terraform

```bash
cd terraform
terraform init
terraform apply
cd ..
```

Terraform will show a plan and ask for confirmation. Type `yes`. When it finishes (~1–2 min) it prints the instance ID and nmap command, and auto-populates `ansible/inventory/hosts.ini`.

### Step 6 — Configure and deploy with Ansible

```bash
ansible-playbook site.yml
```

This SSHs into the instance, installs Docker, deploys the container, and starts the Minecraft service. Takes around 2–3 minutes. When it finishes the server is live.

---

## Verify the Server is Running

Use the nmap command printed by Terraform:

```bash
nmap -sV -Pn -p T:25565 <PUBLIC_IP>
```

Expected output:

```
PORT      STATE SERVICE   VERSION
25565/tcp open  minecraft Minecraft 1.21.x (Protocol: ...)
```

---

## Auto-Start and Graceful Shutdown

The `minecraft` systemd service is configured to:

- **Auto-start** on boot via `systemctl enable`
- **Stop gracefully** — `ExecStop` sends `rcon-cli stop` to the server before docker compose tears down the container, giving the world time to save
- **Auto-restart** on failure via `Restart=on-failure`

To verify after a reboot:

```bash
aws ec2 reboot-instances --instance-ids <INSTANCE_ID>
# Wait ~60 seconds
nmap -sV -Pn -p T:25565 <PUBLIC_IP>
```

---

## Teardown

When done, destroy all AWS resources to avoid charges:

```bash
bash teardown.sh
```

---

## Resources & Sources

- [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) — Docker image used for the server
- [Terraform AWS Provider docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Ansible community.docker collection](https://docs.ansible.com/ansible/latest/collections/community/docker/)
- [AWS EC2 documentation](https://docs.aws.amazon.com/ec2/)
- [systemd service units](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [Docker Compose reference](https://docs.docker.com/compose/compose-file/)