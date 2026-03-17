.PHONY: help install deploy deploy-addons destroy verify test status logs clean

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install-check: ## Check if required dependencies are installed
	@echo "🔧 Checking dependencies..."
	@command -v terraform >/dev/null 2>&1 || { echo "Please install Terraform"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "Please install kubectl"; exit 1; }
	@command -v aws >/dev/null 2>&1 || { echo "Please install AWS CLI"; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo "Please install Helm"; exit 1; }
	@echo "✅ All dependencies are installed"

validate: ## Validate Terraform configuration
	@echo "🔍 Validating Terraform configuration..."
	@cd terraform && terraform fmt -check
	@cd terraform && terraform validate
	@echo "✅ Terraform configuration is valid"

plan: ## Plan Terraform deployment
	@echo "📋 Planning Terraform deployment..."
	@cd terraform && terraform init && terraform plan

deploy: ## Deploy the complete EKS cluster with add-ons
	@echo "🚀 Deploying EKS cluster with add-ons..."
	@chmod +x scripts/deploy.sh
	@./scripts/deploy.sh

deploy-addons: ## Deploy only cluster add-ons (assumes cluster exists)
	@echo "🚀 Deploying cluster add-ons only..."
	@chmod +x scripts/deploy.sh
	@DEPLOY_K8S_ONLY=true ./scripts/deploy.sh

destroy: ## Destroy all infrastructure (use FORCE=true to skip confirmation)
	@echo "🗑️ Destroying infrastructure..."
	@chmod +x scripts/destroy.sh
	@./scripts/destroy.sh $(if $(filter true,$(FORCE)),--force)

verify: ## Verify cluster health, CloudWatch logs, and metrics
	@chmod +x scripts/verify.sh
	@./scripts/verify.sh

test: verify ## Alias for verify

status: ## Show status of all components
	@echo "📊 Checking infrastructure status..."
	@echo "🏗️ Terraform Status:"
	@cd terraform && terraform show -json | jq -r '.values.root_module.resources[] | select(.type == "aws_eks_cluster") | "EKS Cluster: " + .values.name' 2>/dev/null || echo "No EKS cluster found"
	@echo ""
	@echo "☸️ Kubernetes Status:"
	@kubectl get nodes -o wide 2>/dev/null || echo "❌ Cluster not accessible"
	@echo ""
	@echo "🔗 Services:"
	@kubectl get svc -A -o wide 2>/dev/null || echo "❌ No services found"
	@echo ""
	@echo "📦 Pods:"
	@kubectl get pods -A 2>/dev/null || echo "❌ No pods found"

logs: ## Show logs for all components
	@echo "📜 Cluster logs:"
	@kubectl get pods -A --no-headers | head -10 | awk '{print "Namespace: " $$1 " Pod: " $$2}' | while read line; do echo "$$line"; done

port-forward-grafana: ## Port-forward Grafana to localhost:3000
	@echo "🌐 Port-forwarding Grafana to http://localhost:3000"
	@kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

test-connectivity: ## Test connectivity to cluster
	@echo "🔍 Testing cluster connectivity..."
	@kubectl get nodes 2>/dev/null && echo "✅ Cluster is accessible" || echo "❌ Cannot connect to cluster"

clean: ## Clean up local files
	@echo "🧹 Cleaning up local files..."
	@echo "⚠️  This will remove:"
	@echo "   - terraform/.terraform directory"
	@echo "   - terraform state files"
	@echo "   - terraform lock file"
	@read -p "Are you sure you want to continue? [y/N]: " confirm && [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ] || (echo "❌ Cleanup cancelled" && exit 1)
	@rm -rf terraform/.terraform
	@rm -f terraform/terraform.tfstate*
	@rm -f terraform/.terraform.lock.hcl
	@echo "✅ Local cleanup completed"

format: ## Format all configuration files
	@echo "🎨 Formatting files..."
	@cd terraform && terraform fmt
	@echo "✅ Files formatted"

security-scan: ## Run security scan on Terraform files
	@echo "🔒 Running security scan..."
	@command -v checkov >/dev/null 2>&1 && cd terraform && checkov -d . || echo "Install checkov for security scanning"

clean-addons: ## Clean up cluster add-ons
	@echo "🗑️ Cleaning up cluster add-ons..."
	@echo "Uninstalling Prometheus..."
	@helm uninstall prometheus -n monitoring 2>/dev/null || echo "No Prometheus installation found"
	@echo "Uninstalling Cluster Autoscaler..."
	@helm uninstall cluster-autoscaler -n kube-system 2>/dev/null || echo "No Cluster Autoscaler installation found"
	@echo "Uninstalling AWS Load Balancer Controller..."
	@helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || echo "No AWS Load Balancer Controller installation found"
	@echo "✅ Add-ons cleanup completed"

cleanup-external: ## Clean up external AWS resources (Load Balancers, Security Groups, etc.)
	@echo "🗑️ Cleaning up external AWS resources..."
	@chmod +x scripts/destroy.sh
	@CLUSTER_NAME=$${CLUSTER_NAME:-eks-cluster} AWS_REGION=$${AWS_REGION:-eu-west-1} bash -c 'source scripts/destroy.sh && cleanup_external_resources'
