# setup script to check requirements and initialize Terraform  

set -e
 
# Check AWS CLI
if ! command -v aws &> /dev/null; then
  echo ERROR: AWS CLI is not installed.
  exit 1
fi
 
# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
  echo ERROR: AWS credentials are not set or expired.
  echo Paste fresh credentials from Learner Lab into /Users/jin/.aws/credentials
  exit 1
fi
 
# Check Terraform
if ! command -v terraform &> /dev/null; then
  echo ERROR: Terraform is not installed.
  echo Install it from: https://developer.hashicorp.com/terraform/install
  exit 1
fi
 
# Check Ansible
if ! command -v ansible-playbook &> /dev/null; then
  echo ERROR: Ansible is not installed. Run: pip install ansible
  exit 1
fi
 
# Generate SSH key if it doesn't exist
if [ ! -f ~/.ssh/minecraft-key ]; then
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/minecraft-key -N 
fi
 
# Install Ansible collections
cd ..
ansible-galaxy collection install -r ansible/requirements.yml
 
# Initialize Terraform
cd terraform
terraform init
cd ..
 
echo Setup complete. Run ./deploy.sh to deploy the server.
 
