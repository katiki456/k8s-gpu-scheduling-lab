CLUSTER := gpu-lab
KUBECTL := kubectl --context kind-$(CLUSTER)
HELM    := helm --kube-context kind-$(CLUSTER)

.PHONY: up down gpu monitoring keda vllm all status grafana load

all: up gpu monitoring keda vllm  ## Bring up the entire lab

up:  ## Create the kind cluster with a labeled GPU node pool
	kind create cluster --config cluster/kind-config.yaml

down:  ## Delete the cluster
	kind delete cluster --name $(CLUSTER)

gpu:  ## Install fake-gpu-operator (simulated GPUs + DCGM metrics)
	$(HELM) upgrade -i gpu-operator fake-gpu-operator \
		--repo https://fake-gpu-operator.storage.googleapis.com \
		-n gpu-operator --create-namespace \
		-f manifests/gpu/fake-gpu-operator-values.yaml

monitoring:  ## Install kube-prometheus-stack + GPU dashboard
	$(HELM) upgrade -i kube-prometheus-stack kube-prometheus-stack \
		--repo https://prometheus-community.github.io/helm-charts \
		-n monitoring --create-namespace \
		-f manifests/monitoring/kube-prometheus-values.yaml
	$(KUBECTL) -n monitoring create configmap gpu-lab-dashboard \
		--from-file=dashboards/gpu-lab-dashboard.json \
		--dry-run=client -o yaml | $(KUBECTL) apply -f -
	$(KUBECTL) apply -f manifests/monitoring/dcgm-servicemonitor.yaml

keda:  ## Install KEDA
	$(HELM) upgrade -i keda keda \
		--repo https://kedacore.github.io/charts \
		-n keda --create-namespace

vllm:  ## Deploy the inference workload + service + autoscaler
	$(KUBECTL) create namespace inference --dry-run=client -o yaml | $(KUBECTL) apply -f -
	$(KUBECTL) apply -f manifests/vllm/deployment.yaml
	$(KUBECTL) apply -f manifests/keda/scaledobject.yaml

status:  ## Show GPU capacity, pods, and HPA state
	$(KUBECTL) get nodes -L node-pool -o wide
	@echo
	$(KUBECTL) get nodes -o custom-columns='NODE:.metadata.name,GPUs:.status.capacity.nvidia\.com/gpu'
	@echo
	$(KUBECTL) get pods -A | grep -E 'inference|gpu-operator|keda|monitoring' || true
	@echo
	$(KUBECTL) -n inference get scaledobject,hpa,deploy

grafana:  ## Port-forward Grafana to http://localhost:3000 (admin / gpu-lab)
	$(KUBECTL) -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80

load:  ## Generate traffic against the inference service
	./scripts/load.sh
