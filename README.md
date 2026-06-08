# 🎮 Minecraft Server on AWS — Infrastructure as Code

Automated deployment of a Minecraft Java Edition server on AWS EC2 using **Ansible** and **Docker**. No AWS Console interaction required after initial credential setup.

---

## Background

### What are we doing?

This project takes the manual Minecraft server setup from Part 1 and fully automates it. A single command provisions the AWS infrastructure, configures the EC2 instance, deploys the server inside a Docker container, and sets it up to auto-restart on reboot — all without ever touching the AWS Management Console.

### How does it work?

There are three stages, each handled by a dedicated Ansible role:

1. **Provision** — Creates the AWS resources: VPC, subnet, internet gateway, route table, security group, key pair, and EC2 instance. Uses the `amazon.aws` Ansible collection (backed by `boto3`) to interact with AWS APIs directly from your local machine.

2. **Configure** — SSHs into the freshly launched EC2 instance and installs Docker. Then copies over a `docker-compose.yml` and a `systemd` service unit so the server starts on boot and shuts down gracefully.

3. **Deploy** — Pulls the [`itzg/minecraft-server`](https://github.com/itzg/docker-minecraft-server) Docker image and starts the Minecraft service.

### Why Docker?

Running Minecraft inside a Docker container gives us a few things for free: the image handles Java and all server dependencies, the `stop_grace_period` setting ensures the world gets saved before the container stops (fixing the improper shutdown issue from Part 1), and it's easy to upgrade the server version by just changing a variable.

---

## Pipeline Diagram

```
Local Machine
│
├─ ansible-playbook site.yml
│
├──► [Stage 1: Provision]  ─────────────────────────────────────────────►  AWS
│      roles/provision                                                     │
│      • Generate SSH key pair                                             ├─ VPC + Subnet + IGW + Route Table
│      • Upload public key to AWS                                          ├─ Security Group (ports 22, 25565)
│      • Create VPC / networking                                           ├─ EC2 t3.medium (Ubuntu 24.04)
│      • Launch EC2 instance                                               └─ Key Pair
│      • Write dynamic inventory (hosts.ini)
│
├──► [Stage 2: Configure]  ──────────────────────────────────────────────► EC2 Instance
│      roles/configure                                                     │
│      • Install Docker Engine + Compose plugin                            ├─ Docker installed
│      • Create /opt/minecraft data directory                              ├─ docker-compose.yml written
│      • Template docker-compose.yml                                       └─ minecraft.service enabled
│      • Template + enable systemd minecraft.service
│
└──► [Stage 3: Deploy]  ─────────────────────────────────────────────────► EC2 Instance
       roles/docker                                                        │
       • Pull itzg/minecraft-server image                                  ├─ Container running
       • Start minecraft systemd service                                   └─ Port 25565 open
       • Wait for port 25565 to be ready
```

---

## Requirements

### Tools

| Tool | Version | Install |
|------|---------|---------|
| Python | ≥ 3.10 | [python.org](https://www.python.org/) |
| Ansible | ≥ 2.15 | `pip install ansible` |
| boto3 | ≥ 1.28 | `pip install boto3 botocore` |
| AWS CLI | ≥ 2.x | [AWS CLI install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| nmap | any | `brew install nmap` / `apt install nmap` |

### Ansible Collections

Install with one command (see [Running the Pipeline](#running-the-pipeline)):

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

The `requirements.yml` installs:
- `amazon.aws` ≥ 7.0 — AWS resource management
- `community.docker` ≥ 3.0 — Docker image management
- `community.crypto` ≥ 2.0 — SSH key generation

### AWS Credentials

This project uses [AWS Academy Learner Lab](https://awsacademy.instructure.com/) credentials. You need to export them as environment variables **before** running any playbook.

1. Open your Learner Lab and click **AWS Details > AWS CLI**.
2. Copy the three credential values.
3. Export them in your terminal:

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_SESSION_TOKEN="your-session-token"
export AWS_DEFAULT_REGION="us-east-1"
```

> **Note:** Learner Lab credentials expire after a few hours. If a playbook fails with an auth error, re-export fresh credentials from the Learner Lab panel.

### No other configuration is required before running.

All variables have defaults in [`ansible/group_vars/all.yml`](ansible/group_vars/all.yml). You can override any of them at runtime using `-e key=value`.

---

## Repository Structure

```
minecraft-iac/
├── site.yml                          # Main playbook — runs all three stages
├── teardown.yml                      # Destroys all AWS resources
├── ansible.cfg                       # Ansible configuration
├── .gitignore
│
└── ansible/
    ├── requirements.yml              # Collection dependencies
    ├── group_vars/
    │   └── all.yml                   # Default variables
    ├── inventory/
    │   └── hosts.ini                 # Auto-generated by provision role
    └── roles/
        ├── provision/
        │   └── tasks/main.yml        # AWS infrastructure
        ├── configure/
        │   ├── tasks/main.yml        # Docker + systemd setup
        │   └── templates/
        │       ├── docker-compose.yml.j2
        │       └── minecraft.service.j2
        └── docker/
            └── tasks/main.yml        # Pull image + start service
```

---

## Running the Pipeline

### Step 1 — Clone the repo

```bash
git clone https://github.com/<your-username>/minecraft-iac.git
cd minecraft-iac
```

### Step 2 — Install dependencies

```bash
pip install ansible boto3 botocore
ansible-galaxy collection install -r ansible/requirements.yml
```

### Step 3 — Export AWS credentials

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
export AWS_DEFAULT_REGION="us-east-1"
```

### Step 4 — Run the full pipeline

```bash
ansible-playbook site.yml
```

This runs all three stages back-to-back. The whole thing takes around **3–5 minutes**. At the end, you'll see the public IP of your instance printed in the output.

### Optional: Run stages individually

If you want to run one stage at a time (e.g., after a crash or for debugging):

```bash
# Stage 1 only — provision AWS resources
ansible-playbook site.yml --tags provision

# Stage 2 only — configure the EC2 instance (requires hosts.ini to be populated)
ansible-playbook site.yml --tags configure

# Stage 3 only — deploy the Docker container
ansible-playbook site.yml --tags deploy
```

> **Note:** Tags need to be added to `site.yml`'s plays if you want to use this approach — see [Ansible tags docs](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_tags.html).

### Customizing variables

Override any default variable at runtime:

```bash
# Use a bigger instance
ansible-playbook site.yml -e instance_type=t3.large

# Change the server MOTD and max players
ansible-playbook site.yml -e minecraft_motd="My Server" -e minecraft_max_players=10

# Restrict SSH to your IP only
ansible-playbook site.yml -e ssh_allowed_cidr=203.0.113.5/32
```

---

## Connecting to the Minecraft Server

Once the playbook finishes, grab the public IP from the output (or from `ansible/inventory/hosts.ini`) and run:

```bash
nmap -sV -Pn -p T:25565 <PUBLIC_IP>
```

A successful response looks like:

```
PORT      STATE SERVICE   VERSION
25565/tcp open  minecraft Minecraft 1.21.x (Protocol: ...)
```

To connect in-game, open Minecraft Java Edition, go to **Multiplayer > Add Server**, and enter the public IP as the server address.

---

## Auto-Start and Graceful Shutdown

The Minecraft service is managed by `systemd`. It's set to:

- **Auto-start** on boot via `systemctl enable minecraft`
- **Gracefully stop** using `docker compose exec minecraft rcon-cli stop` before taking the container down — this tells the server to save the world and disconnect players cleanly before shutting down (fixes the improper shutdown bug from Part 1)
- **Auto-restart** on failure via `Restart=on-failure`

To verify after a reboot:

```bash
# Check service status
systemctl status minecraft

# Or check the logs
journalctl -u minecraft -n 50
```

---

## Teardown

When you're done, run the teardown playbook to delete all AWS resources and avoid charges:

```bash
ansible-playbook teardown.yml
```

It will prompt you to type `yes` to confirm before deleting anything.

---

## Resources & Sources

- [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) — the Docker image used for the server
- [amazon.aws Ansible collection docs](https://docs.ansible.com/ansible/latest/collections/amazon/aws/)
- [community.docker Ansible collection docs](https://docs.ansible.com/ansible/latest/collections/community/docker/)
- [AWS EC2 docs](https://docs.aws.amazon.com/ec2/)
- [systemd service units](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [Docker Compose reference](https://docs.docker.com/compose/compose-file/)
- [Ansible Playbook best practices](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html)
