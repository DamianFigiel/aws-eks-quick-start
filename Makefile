.PHONY: help install deploy destroy status logs clean

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install: ## Install required dependencies
	@echo "🔧 Installing dependencies..."
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

deploy: ## Deploy the complete infrastructure
	@echo "🚀 Deploying infrastructure..."
	@chmod +x scripts/deploy.sh
	@./scripts/deploy.sh

destroy: ## Destroy all infrastructure
	@echo "🗑️ Destroying infrastructure..."
	@chmod +x scripts/destroy.sh
	@./scripts/destroy.sh

status: ## Show status of all components
	@echo "📊 Checking infrastructure status..."
	@echo "🏗️ Terraform Status:"
	@cd terraform && terraform show -json | jq -r '.values.root_module.resources[] | select(.type == "aws_eks_cluster") | "EKS Cluster: " + .values.name'
	@echo ""
	@echo "☸️ Kubernetes Status:"
	@kubectl get nodes -o wide || echo "❌ Cluster not accessible"
	@echo ""
	@echo "🔗 Services:"
	@kubectl get svc -n rollup -o wide || echo "❌ Rollup namespace not found"
	@kubectl get svc -n ethereum -o wide || echo "❌ Ethereum namespace not found"
	@echo ""
	@echo "📦 Pods:"
	@kubectl get pods -n rollup || echo "❌ Rollup namespace not found"
	@kubectl get pods -n ethereum || echo "❌ Ethereum namespace not found"

logs-rollup: ## Show logs for rollup components
	@echo "📜 Rollup logs:"
	@kubectl logs -l app=op-geth -n rollup --tail=50

logs-ethereum: ## Show logs for Ethereum components
	@echo "📜 Ethereum logs:"
	@kubectl logs -l app=execution-client -n ethereum --tail=50

logs: logs-rollup logs-ethereum ## Show logs for all components

port-forward-grafana: ## Port-forward Grafana to localhost:3000
	@echo "🌐 Port-forwarding Grafana to http://localhost:3000"
	@kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

port-forward-rollup: ## Port-forward rollup RPC to localhost:8545
	@echo "🌐 Port-forwarding rollup RPC to http://localhost:8545"
	@kubectl port-forward -n rollup svc/op-geth 8545:8545

test-connectivity: ## Test connectivity to rollup RPC
	@echo "🔍 Testing rollup connectivity..."
	@kubectl get svc -n rollup op-geth-external -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' | xargs -I {} curl -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://{}:8545 || echo "❌ RPC not accessible"

clean: ## Clean up local files
	@echo "🧹 Cleaning up local files..."
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