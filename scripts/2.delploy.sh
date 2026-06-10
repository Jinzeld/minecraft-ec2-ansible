# deploy script for terraform and Ansible 

set -e
 
# Check dependencies
if ! command -v terraform &> /dev/null; then
  echo "ERROR: Terraform is not installed. Run ./setup.sh first."
  exit 1
fi
 
if ! command -v ansible-playbook &> /dev/null; then
  echo "ERROR: Ansible is not installed. Run ./setup.sh first."
  exit 1
fi
 
if [ ! -f ~/.ssh/minecraft-key ]; then
  echo "ERROR: SSH key not found. Run ./setup.sh first."
  exit 1
fi
 
if ! aws sts get-caller-identity &> /dev/null; then
  echo "ERROR: AWS credentials are not set or expired."
  echo "Paste fresh credentials from Learner Lab into ~/.aws/credentials"
  exit 1
fi
 
# Stage 1 - Terraform
echo "Provisioning AWS infrastructure..."
cd ../terraform
terraform apply -auto-approve
cd ..
 
# Wait for SSH to be ready
echo "Waiting for SSH..."
PUBLIC_IP=$(cd terraform && terraform output -raw nmap_command | awk '{print $NF}')
for i in {1..30}; do
  if ssh -i ~/.ssh/minecraft-key \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=5 \
    ubuntu@$PUBLIC_IP "exit" &> /dev/null; then
    break
  fi
  echo "Retrying SSH ($i/30)..."
  sleep 10
done
 
# Stage 2 - Ansible
echo "Configuring and deploying Minecraft server..."
ansible-playbook site.yml
 
echo "Done. Run: nmap -sV -Pn -p T:25565 $PUBLIC_IP"