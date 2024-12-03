## Prerequisites

Before getting started, ensure you have the following tools installed:

- **Docker**: Required for building and pushing container images
- **kubectl**: The Kubernetes command-line tool for cluster management
- **KinD (Kubernetes in Docker)**: For running a local Kubernetes cluster
- **Helm**: The package manager for Kubernetes, used for deploying monitoring and logging stacks

You can verify your installations by running:
```bash
make check-prerequisites
```

## Project Structure

The project is organized into several key directories:

```
.
├── src/
│   ├── backend/             # Backend service
│   │   └── kubernetes-manifests/  # Contains service monitors and deployments
│   └── frontend/            # Frontend service
│       └── kubernetes-manifests/  # Contains service monitors and deployments
└── infrastructure/
    ├── logging/            # Logging configuration
    │   ├── fluentbit/
    │   └── loki/
    └── monitoring/         # Monitoring configuration
        ├── prometheus/
        ├── alertmanager/
        └── grafana/
```

## Quick Start

1. **Create the Local Environment**:
   ```bash
   # Create a KinD cluster and local registry
   make create-cluster create-registry
   ```

2. **Set Up Monitoring and Logging Infrastructure**:
   ```bash
   # Install monitoring stack (Prometheus, Grafana, AlertManager)
   make install-monitoring
   
   # Install logging stack (Loki, Fluent Bit)
   make install-logging
   ```

   This step must come before deploying applications because:
   - The ServiceMonitor custom resources need to be available in the cluster
   - Prometheus operator needs to be running to recognize these ServiceMonitors
   - Applications' metrics endpoints will be automatically discovered and scraped from the moment they start

3. **Build and Deploy the Application**:
   ```bash
   # Build and push both frontend and backend images
   make build push
   
   # Deploy the application to Kubernetes
   make deploy
   ```

4. **Verify the Setup**:
   ```bash
   # Check all components are running properly
   make status
   
   # Get Grafana admin password
   make get-grafana-password
   
   # Forward Grafana port to localhost:3000
   make port-forward
   ```

   After port forwarding, you can access Grafana at http://localhost:3000 and verify that your application metrics are being collected.

## Available Make Targets

### Cluster Management
- `make create-cluster`: Creates a new KinD cluster
- `make create-registry`: Sets up a local Docker registry

### Monitoring Setup
- `make install-monitoring`: Sets up the complete monitoring stack
- `make install-prometheus`: Installs Prometheus
- `make install-grafana`: Installs Grafana
- `make install-rules`: Applies Prometheus rules and Alertmanager config

### Logging Setup
- `make install-logging`: Sets up the complete logging stack
- `make install-loki`: Installs Loki
- `make install-fluentbit`: Installs Fluent Bit

### Build and Deployment
- `make build`: Builds both frontend and backend images
- `make push`: Pushes images to the registry
- `make deploy`: Deploys the application to Kubernetes
- `make backend`: Builds and pushes only the backend
- `make frontend`: Builds and pushes only the frontend

### Utility Commands
- `make status`: Shows cluster and application status
- `make get-grafana-password`: Retrieves Grafana admin password
- `make port-forward`: Sets up port forwarding for Grafana UI

### Cleanup
- `make clean`: Removes all resources
- `make uninstall-monitoring`: Removes monitoring stack
- `make uninstall-logging`: Removes logging stack

## Configuration

### Registry Configuration
- Default registry: `localhost:5000`
- Registry name: `kind-registry`
- Registry port: `5000`

### Namespace Configuration
- Monitoring: `monitoring`
- Logging: `logging`
- Loki: `loki`
- Grafana: `grafana`

## Monitoring and Logging

The project includes a comprehensive monitoring and logging stack:

- **Prometheus**: For metrics collection and alerting
  - Uses ServiceMonitor resources to automatically discover and scrape metrics from your applications
  - Configured through values in `infrastructure/monitoring/prometheus/prometheus-values.yaml`
  - Custom alerting rules defined in `infrastructure/monitoring/prometheus/prometheus-rules.yaml`

- **Grafana**: For metrics visualization and dashboarding
  - Configured through values in `infrastructure/monitoring/grafana/grafana-values.yaml`
  - Automatically connected to Prometheus and Loki data sources

- **Loki**: For log aggregation
  - Configured through values in `infrastructure/logging/loki/loki-values.yaml`
  - Provides a centralized logging solution

- **Fluent Bit**: For log collection and forwarding
  - Configured through values in `infrastructure/logging/fluentbit/fluentbit-values.yaml`
  - Automatically collects container logs and forwards them to Loki

Access Grafana dashboards at `http://localhost:3000` after running `make port-forward`.

## Troubleshooting

If you encounter issues:

1. Check the cluster status:
   ```bash
   make status
   ```

2. Verify all pods are running:
   ```bash
   kubectl get pods --all-namespaces
   ```

3. Check component logs:
   ```bash
   kubectl logs -n <namespace> <pod-name>
   ```

4. Verify ServiceMonitor resources:
   ```bash
   kubectl get servicemonitors --all-namespaces
   ```

5. Check Prometheus targets:
   ```bash
   # Port forward Prometheus UI
   kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
   ```
   Then visit http://localhost:9090/targets to ensure your applications are being scraped.

For cleanup and fresh start:
```bash
make clean
make all
```
