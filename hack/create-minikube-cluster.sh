#!/usr/bin/env bash

# Copyright 2025 The PipeCD Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

CLUSTER=${1:-pipecd}
REG_NAME='kind-registry'
REG_PORT='5001'
MINIKUBE_DRIVER=${MINIKUBE_DRIVER:-docker}

# Create docker volume for pipecd data unless it already exists
echo "Creating pipecd-data volume..."
if ! docker volume ls | grep -q pipecd-data; then
  docker volume create pipecd-data
fi

# Get the registry IP address
# For Docker driver, we need to get the host IP that Minikube can access
if [ "${MINIKUBE_DRIVER}" = "docker" ]; then
  # With Docker driver, Minikube runs in a container, so we need host.docker.internal
  # or the actual host IP. On Linux, we use host network or get gateway IP.
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # On Linux, get the Docker bridge network gateway
    REG_HOST=$(docker network inspect bridge --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || echo "172.17.0.1")
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    # On macOS, use host.docker.internal
    REG_HOST="host.docker.internal"
  else
    # Fallback for other systems
    REG_HOST="host.docker.internal"
  fi
else
  # For other drivers (like hyperkit, virtualbox), use localhost
  REG_HOST="localhost"
fi

# Check if Minikube cluster already exists
if minikube status -p "${CLUSTER}" &>/dev/null; then
  echo "Minikube cluster '${CLUSTER}' already exists. Starting it..."
  minikube start -p "${CLUSTER}" --driver="${MINIKUBE_DRIVER}"
else
  echo "Creating Minikube cluster '${CLUSTER}' with driver '${MINIKUBE_DRIVER}'..."
  # Start Minikube with Docker driver
  minikube start -p "${CLUSTER}" \
    --driver="${MINIKUBE_DRIVER}" \
    --container-runtime=containerd
fi

# Ensure kubectl context is set
minikube kubectl --profile "${CLUSTER}" -- config use-context "${CLUSTER}"

# Create pipecd namespace
echo "Creating pipecd namespace..."
minikube kubectl --profile "${CLUSTER}" -- create namespace pipecd --dry-run=client -o yaml | minikube kubectl --profile "${CLUSTER}" -- apply -f -

# Configure Minikube to use the local registry
echo "Configuring Minikube to use local registry at ${REG_HOST}:${REG_PORT}..."

# For Docker driver, we need to configure containerd inside the Minikube VM/container
if [ "${MINIKUBE_DRIVER}" = "docker" ]; then
  # Get the Minikube container name (it might be named differently)
  MINIKUBE_CONTAINER=$(docker ps --filter "name=${CLUSTER}" --format "{{.Names}}" | head -n1)
  
  # If not found, try to find by label
  if [ -z "${MINIKUBE_CONTAINER}" ]; then
    MINIKUBE_CONTAINER=$(docker ps --filter "label=created_by.minikube.sigs.k8s.io=true" --filter "label=name=${CLUSTER}" --format "{{.Names}}" | head -n1)
  fi
  
  if [ -n "${MINIKUBE_CONTAINER}" ]; then
    # Get the network that Minikube container is using
    MINIKUBE_NETWORK=$(docker inspect "${MINIKUBE_CONTAINER}" --format '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}}{{end}}' | head -n1)
    
    if [ -n "${MINIKUBE_NETWORK}" ] && [ "${MINIKUBE_NETWORK}" != "bridge" ]; then
      # Connect registry to Minikube's network if not already connected
      if ! docker inspect "${REG_NAME}" --format '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}} {{end}}' 2>/dev/null | grep -q "${MINIKUBE_NETWORK}"; then
        echo "Connecting registry to Minikube network: ${MINIKUBE_NETWORK}"
        docker network connect "${MINIKUBE_NETWORK}" "${REG_NAME}" 2>/dev/null || echo "Warning: Could not connect registry to Minikube network"
      fi
    fi
    
    # Configure containerd in Minikube to use the local registry
    REG_CONFIG_DIR="/etc/containerd/certs.d"
    docker exec "${MINIKUBE_CONTAINER}" /bin/bash -c "
      set -o errexit
      set -o nounset
      set -o pipefail
      
      REG_HOST=\"${REG_HOST}\"
      REG_PORT=\"${REG_PORT}\"
      REG_CONFIG_DIR=\"${REG_CONFIG_DIR}\"
      
      mkdir -p \"\${REG_CONFIG_DIR}/localhost:\${REG_PORT}\"
      cat > \"\${REG_CONFIG_DIR}/localhost:\${REG_PORT}/hosts.toml\" <<EOF
server = \"http://\${REG_HOST}:\${REG_PORT}\"

[host.\"http://\${REG_HOST}:\${REG_PORT}\"]
  capabilities = [\"pull\", \"resolve\", \"push\"]
  skip_verify = true
  plain-http = true
EOF
      systemctl restart containerd || true
    " || echo "Warning: Could not configure containerd in Minikube container. You may need to configure it manually."
  else
    echo "Warning: Could not find Minikube container. Registry configuration may need to be done manually."
  fi
else
  # For non-Docker drivers, configure via SSH
  echo "Configuring registry for non-Docker driver..."
  REG_HOST_ESCAPED="${REG_HOST}"
  REG_PORT_ESCAPED="${REG_PORT}"
  minikube ssh -p "${CLUSTER}" -- "
    REG_HOST=\"${REG_HOST_ESCAPED}\"
    REG_PORT=\"${REG_PORT_ESCAPED}\"
    sudo mkdir -p /etc/containerd/certs.d/localhost:\${REG_PORT}
    sudo tee /etc/containerd/certs.d/localhost:\${REG_PORT}/hosts.toml > /dev/null <<EOF
server = \"http://\${REG_HOST}:\${REG_PORT}\"

[host.\"http://\${REG_HOST}:\${REG_PORT}\"]
  capabilities = [\"pull\", \"resolve\", \"push\"]
  skip_verify = true
  plain-http = true
EOF
    sudo systemctl restart containerd || true
  " || echo "Warning: Could not configure containerd via SSH. You may need to configure it manually."
fi

# Mount the pipecd-data volume into Minikube
# For Docker driver, we can use hostPath mounts
if [ "${MINIKUBE_DRIVER}" = "docker" ]; then
  VOLUME_MOUNT_POINT=$(docker volume inspect pipecd-data --format '{{ .Mountpoint }}')
  echo "Volume mount point: ${VOLUME_MOUNT_POINT}"
  # Note: Minikube with Docker driver can access host paths directly
  # We'll create a PersistentVolume and PersistentVolumeClaim for this
  cat <<EOF | minikube kubectl --profile "${CLUSTER}" -- apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pipecd-data
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: ${VOLUME_MOUNT_POINT}
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pipecd-data
  namespace: pipecd
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF
fi

# Document the local registry
# https://github.com/kubernetes/enhancements/tree/master/keps/sig-cluster-lifecycle/generic/1755-communicating-a-local-registry
cat <<EOF | minikube kubectl --profile "${CLUSTER}" -- apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "${REG_HOST}:${REG_PORT}"
    help: "https://minikube.sigs.k8s.io/docs/handbook/registry/"
EOF

echo "Minikube cluster '${CLUSTER}' is ready!"
echo "To use this cluster, run: minikube kubectl --profile ${CLUSTER} -- config use-context ${CLUSTER}"
echo "Or export kubeconfig: export KUBECONFIG=\$(minikube kubectl --profile ${CLUSTER} -- config view --flatten --minify)"
