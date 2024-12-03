# Docker Registry Configuration
REGISTRY ?= localhost:5000
REG_NAME ?= kind-registry
REG_PORT ?= 5000

# Image Configuration
BACKEND_IMAGE := $(REGISTRY)/python-guestbook-backend
FRONTEND_IMAGE := $(REGISTRY)/python-guestbook-frontend
VERSION ?= latest

# Infrastructure directory
INFRA_DIRECTORY := infrastructure
LOGGING_DIRECTORY := $(INFRA_DIRECTORY)/logging
MONITORING_DIRECTORY := $(INFRA_DIRECTORY)/monitoring

# Cluster Configuration
CLUSTER_NAME ?= kind
CLUSTER_CONFIG := $(INFRA_DIRECTORY)/cluster.yaml

# Namespace Definitions
MONITORING_NAMESPACE := monitoring
LOGGING_NAMESPACE := logging
GRAFANA_NAMESPACE := grafana
LOKI_NAMESPACE := loki

# Path Configurations
BACKEND_DIR := src/backend
BACKEND_MANIFESTS := $(BACKEND_DIR)/kubernetes-manifests/
FRONTEND_DIR := src/frontend
FRONTEND_MANIFESTS := $(FRONTEND_DIR)/kubernetes-manifests/

# Monitoring Configurations
PROMETHEUS_VALUES := $(MONITORING_DIRECTORY)/prometheus/prometheus-values.yaml
PROMETHEUS_RULES := $(MONITORING_DIRECTORY)/prometheus/prometheus-rules.yaml
ALERTMANAGER_CONFIG := $(MONITORING_DIRECTORY)/alertmanager/
GRAFANA_VALUES := $(MONITORING_DIRECTORY)/grafana/grafana-values.yaml

# Logging Configurations
FLUENTBIT_VALUES := $(LOGGING_DIRECTORY)/fluentbit/fluentbit-values.yaml
LOKI_VALUES := $(LOGGING_DIRECTORY)/loki/loki-values.yaml

# Default target
.PHONY: all
all: create-cluster create-registry install-logging install-monitoring build push deploy 

# ==============================================================================
# Prerequisite Checks
# ==============================================================================

.PHONY: check-prerequisites
check-prerequisites:
	@echo "Checking prerequisites..."
	@which kubectl >/dev/null || (echo "kubectl is required but not installed" && exit 1)
	@which docker >/dev/null || (echo "docker is required but not installed" && exit 1)
	@which kind >/dev/null || (echo "kind is required but not installed" && exit 1)
	@which helm >/dev/null || (echo "helm is required but not installed" && exit 1)

# ==============================================================================
# Cluster Management
# ==============================================================================

.PHONY: create-cluster
create-cluster: check-prerequisites
	@echo "Creating KinD cluster..."
	@if [ "$$(kind get clusters | grep $(CLUSTER_NAME))" = "" ]; then \
		export REG_NAME=$(REG_NAME) REG_PORT=$(REG_PORT) && \
		envsubst < $(CLUSTER_CONFIG) | kind create cluster --config=-; \
	else \
		echo "Cluster already exists"; \
	fi


.PHONY: create-registry
create-registry:
	@echo "Creating local registry..."
	@if [ "$$(docker ps -q -f name=$(REG_NAME))" = "" ]; then \
		docker run -d --restart=always -p "127.0.0.1:$(REG_PORT):5000" --name "$(REG_NAME)" registry:2; \
	else \
		echo "Registry already exists"; \
	fi
	@if [ "$$(docker network inspect kind -f '{{range .Containers}}{{.Name}}{{end}}' | grep $(REG_NAME))" = "" ]; then \
		docker network connect "kind" "$(REG_NAME)"; \
	fi

# ==============================================================================
# Build and Push
# ==============================================================================

.PHONY: build
build: build-backend build-frontend

.PHONY: build-backend
build-backend:
	@echo "Building backend image..."
	cd $(BACKEND_DIR) && docker build -t $(BACKEND_IMAGE):$(VERSION) .

.PHONY: build-frontend
build-frontend:
	@echo "Building frontend image..."
	cd $(FRONTEND_DIR) && docker build -t $(FRONTEND_IMAGE):$(VERSION) .

.PHONY: push
push: push-backend push-frontend

.PHONY: push-backend
push-backend: build-backend
	@echo "Pushing backend image..."
	docker push $(BACKEND_IMAGE):$(VERSION)

.PHONY: push-frontend
push-frontend: build-frontend
	@echo "Pushing frontend image..."
	docker push $(FRONTEND_IMAGE):$(VERSION)

.PHONY: backend
backend: build-backend push-backend

.PHONY: frontend
frontend: build-frontend push-frontend

# ==============================================================================
# Deployment
# ==============================================================================

.PHONY: deploy
deploy: verify-prerequisites
	@echo "Deploying backend kubernetes resources..."
	kubectl apply -f $(BACKEND_MANIFESTS) || true
	@echo "Deploying frontend kubernetes resources..."
	kubectl apply -f $(FRONTEND_MANIFESTS) || true

.PHONY: verify-prerequisites
verify-prerequisites:
	@echo "Verifying kubernetes connection..."
	@kubectl cluster-info >/dev/null || (echo "No Kubernetes connection" && exit 1)

# ==============================================================================
# Monitoring Setup
# ==============================================================================

.PHONY: install-monitoring
install-monitoring: create-monitoring-namespace install-prometheus install-rules install-grafana

.PHONY: create-monitoring-namespace
create-monitoring-namespace:
	@echo "Creating monitoring namespace..."
	kubectl create namespace $(MONITORING_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

.PHONY: install-prometheus
install-prometheus:
	@echo "Adding Prometheus helm repo..."
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	@echo "Installing Prometheus..."
	helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
		--namespace $(MONITORING_NAMESPACE) \
		-f $(PROMETHEUS_VALUES)

.PHONY: install-rules
install-rules:
	@echo "Applying Prometheus rules..."
	kubectl apply -f $(PROMETHEUS_RULES) -n $(MONITORING_NAMESPACE)
	@echo "Applying Alertmanager config..."
	kubectl apply -f $(ALERTMANAGER_CONFIG) -n $(MONITORING_NAMESPACE)

.PHONY: install-grafana
install-grafana:
	@echo "Adding Grafana helm repo..."
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo update
	@echo "Installing Grafana..."
	helm upgrade --install grafana grafana/grafana \
		--namespace $(MONITORING_NAMESPACE) \
		-f $(GRAFANA_VALUES)

# ==============================================================================
# Logging Setup
# ==============================================================================

.PHONY: install-logging
install-logging: create-logging-namespace create-loki-namespace install-loki install-fluentbit

.PHONY: create-logging-namespace
create-logging-namespace:
	@echo "Creating logging namespace..."
	kubectl create namespace $(LOGGING_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

.PHONY: create-loki-namespace
create-loki-namespace:
	@echo "Creating loki namespace..."
	kubectl create namespace $(LOKI_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

.PHONY: install-loki
install-loki:
	@echo "Installing Loki..."
	helm upgrade --install loki grafana/loki \
		--namespace $(LOKI_NAMESPACE) \
		-f $(LOKI_VALUES)

.PHONY: install-fluentbit
install-fluentbit:
	@echo "Adding Fluent helm repo..."
	helm repo add fluent https://fluent.github.io/helm-charts
	helm repo update
	@echo "Installing Fluent Bit..."
	helm upgrade --install fluent-bit fluent/fluent-bit \
		--namespace $(LOGGING_NAMESPACE) \
		-f $(FLUENTBIT_VALUES)

# ==============================================================================
# Utility
# ==============================================================================

.PHONY: get-grafana-password
get-grafana-password:
	@echo "Grafana admin password:"
	@kubectl get secret --namespace $(MONITORING_NAMESPACE) grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo

.PHONY: port-forward
port-forward:
	@echo "Port forwarding Grafana to localhost:3000..."
	kubectl port-forward -n $(MONITORING_NAMESPACE) svc/grafana 3000:80

.PHONY: status
status:
	@echo "Checking cluster status..."
	@kind get clusters
	@kubectl cluster-info
	@kubectl get nodes
	@echo "\nChecking servic status..."
	@kubectl get pods
	@echo "\nChecking monitoring status..."
	@kubectl get pods -n $(MONITORING_NAMESPACE)
	@echo "\nChecking logging status..."
	@kubectl get pods -n $(LOGGING_NAMESPACE)
	@kubectl get pods -n $(LOKI_NAMESPACE)
	@echo "\nHelm releases:"
	@helm list -A

# ==============================================================================
# Cleanup
# ==============================================================================

.PHONY: clean
clean:
	@echo "Cleaning up..."
	make uninstall-monitoring || true
	make uninstall-logging || true
	kind delete cluster --name $(CLUSTER_NAME) || true
	docker rm -f $(REG_NAME) || true
	docker rmi $(BACKEND_IMAGE):$(VERSION) || true
	docker rmi $(FRONTEND_IMAGE):$(VERSION) || true

.PHONY: uninstall-monitoring
uninstall-monitoring:
	@echo "Uninstalling monitoring stack..."
	helm uninstall prometheus -n $(MONITORING_NAMESPACE) || true
	helm uninstall grafana -n $(MONITORING_NAMESPACE) || true
	kubectl delete -f $(PROMETHEUS_RULES) -n $(MONITORING_NAMESPACE) || true
	kubectl delete -f $(ALERTMANAGER_CONFIG) -n $(MONITORING_NAMESPACE) || true

.PHONY: uninstall-logging
uninstall-logging:
	@echo "Uninstalling logging stack..."
	helm uninstall loki -n $(LOKI_NAMESPACE) || true
	helm uninstall fluent-bit -n $(LOGGING_NAMESPACE) || true
