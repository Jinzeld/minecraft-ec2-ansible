# Destroys all AWS resources created by Terraform.

set -e

echo " This will destroy all Minecraft AWS resources."
read -p "Type 'yes' to confirm: " confirm

if [ "$confirm" != "yes" ]; then
  echo "Aborted."
  exit 1
fi

cd ../terraform
terraform destroy -auto-approve

echo ""
echo " All resources destroyed."
echo "   Clearing Ansible inventory..."

cat > ../ansible/inventory/hosts.ini << 'EOF'
# Cleared by teardown.sh — run terraform apply to repopulate
[minecraft]
EOF

echo "   Done."
