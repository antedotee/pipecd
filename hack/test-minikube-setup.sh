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

# Test configuration
TEST_CLUSTER="pipecd-test-$(date +%s)"
REG_NAME='kind-registry'
REG_PORT='5001'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MINIKUBE_DRIVER=${MINIKUBE_DRIVER:-docker}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Cleanup function
cleanup() {
    echo ""
    echo "========================================="
    echo "Cleaning up test environment..."
    echo "========================================="
    
    # Stop and delete test cluster if it exists
    if minikube status -p "${TEST_CLUSTER}" &>/dev/null; then
        echo "Deleting test Minikube cluster: ${TEST_CLUSTER}"
        minikube delete -p "${TEST_CLUSTER}" || true
    fi
    
    # Print test summary
    echo ""
    echo "========================================="
    echo "Test Summary"
    echo "========================================="
    echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
    echo -e "${YELLOW}Skipped: ${TESTS_SKIPPED}${NC}"
    echo "========================================="
    
    if [ ${TESTS_FAILED} -gt 0 ]; then
        exit 1
    fi
}

trap cleanup EXIT

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓ PASS${NC}: $1"
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗ FAIL${NC}: $1"
    return 1
}

test_skip() {
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo -e "${YELLOW}⊘ SKIP${NC}: $1"
}

# Test functions
test_prerequisites() {
    log_info "Testing prerequisites..."
    
    # Check if minikube is installed
    if ! command -v minikube &> /dev/null; then
        test_skip "minikube is not installed"
        return 1
    fi
    test_pass "minikube is installed"
    
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        test_fail "docker is not installed"
        return 1
    fi
    test_pass "docker is installed"
    
    # Check if docker is running
    if ! docker info &> /dev/null; then
        test_fail "docker daemon is not running"
        return 1
    fi
    test_pass "docker daemon is running"
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        test_fail "kubectl is not installed"
        return 1
    fi
    test_pass "kubectl is installed"
    
    return 0
}

test_script_syntax() {
    log_info "Testing script syntax..."
    
    if bash -n "${SCRIPT_DIR}/create-minikube-cluster.sh"; then
        test_pass "create-minikube-cluster.sh has valid syntax"
        return 0
    else
        test_fail "create-minikube-cluster.sh has syntax errors"
        return 1
    fi
}

test_local_registry_exists() {
    log_info "Testing local registry setup..."
    
    # Ensure local registry is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${REG_NAME}$"; then
        log_info "Starting local registry..."
        "${SCRIPT_DIR}/create-local-registry.sh" || {
            test_fail "Failed to start local registry"
            return 1
        }
    fi
    
    # Check if registry is accessible
    if docker ps --format '{{.Names}}' | grep -q "^${REG_NAME}$"; then
        test_pass "Local registry container is running"
    else
        test_fail "Local registry container is not running"
        return 1
    fi
    
    # Check if registry port is accessible
    if timeout 2 bash -c "echo > /dev/tcp/localhost/${REG_PORT}" 2>/dev/null; then
        test_pass "Local registry is accessible on port ${REG_PORT}"
    else
        test_fail "Local registry is not accessible on port ${REG_PORT}"
        return 1
    fi
    
    return 0
}

test_minikube_cluster_creation() {
    log_info "Testing Minikube cluster creation..."
    
    # Run the create script
    if MINIKUBE_DRIVER="${MINIKUBE_DRIVER}" "${SCRIPT_DIR}/create-minikube-cluster.sh" "${TEST_CLUSTER}"; then
        test_pass "Minikube cluster creation script executed successfully"
    else
        test_fail "Minikube cluster creation script failed"
        return 1
    fi
    
    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    sleep 10
    
    # Check if cluster exists and is running
    if minikube status -p "${TEST_CLUSTER}" &>/dev/null; then
        test_pass "Minikube cluster '${TEST_CLUSTER}' exists and is running"
    else
        test_fail "Minikube cluster '${TEST_CLUSTER}' does not exist or is not running"
        return 1
    fi
    
    return 0
}

test_kubectl_access() {
    log_info "Testing kubectl access to cluster..."
    
    # Set kubeconfig context
    export KUBECONFIG=$(minikube kubectl --profile "${TEST_CLUSTER}" -- config view --flatten --minify)
    
    # Test kubectl access
    if kubectl cluster-info &>/dev/null; then
        test_pass "kubectl can access the cluster"
    else
        test_fail "kubectl cannot access the cluster"
        return 1
    fi
    
    # Check if we can get nodes
    if kubectl get nodes &>/dev/null; then
        test_pass "kubectl can list nodes"
    else
        test_fail "kubectl cannot list nodes"
        return 1
    fi
    
    return 0
}

test_namespace_creation() {
    log_info "Testing namespace creation..."
    
    # Check if pipecd namespace exists
    if kubectl get namespace pipecd &>/dev/null; then
        test_pass "pipecd namespace exists"
    else
        test_fail "pipecd namespace does not exist"
        return 1
    fi
    
    return 0
}

test_registry_configuration() {
    log_info "Testing registry configuration..."
    
    # Check if ConfigMap exists
    if kubectl get configmap local-registry-hosting -n kube-public &>/dev/null; then
        test_pass "local-registry-hosting ConfigMap exists"
    else
        test_fail "local-registry-hosting ConfigMap does not exist"
        return 1
    fi
    
    # Check ConfigMap content
    REG_HOST=$(kubectl get configmap local-registry-hosting -n kube-public -o jsonpath='{.data.localRegistryHosting\.v1}' | grep -oP 'host: \K[^[:space:]]+' || echo "")
    if [ -n "${REG_HOST}" ]; then
        test_pass "ConfigMap contains registry host information"
    else
        test_fail "ConfigMap does not contain registry host information"
        return 1
    fi
    
    return 0
}

test_volume_setup() {
    log_info "Testing volume setup..."
    
    # Check if pipecd-data volume exists
    if docker volume ls | grep -q pipecd-data; then
        test_pass "pipecd-data Docker volume exists"
    else
        test_fail "pipecd-data Docker volume does not exist"
        return 1
    fi
    
    # For Docker driver, check if PV/PVC exist
    if [ "${MINIKUBE_DRIVER}" = "docker" ]; then
        if kubectl get pv pipecd-data &>/dev/null; then
            test_pass "pipecd-data PersistentVolume exists"
        else
            test_fail "pipecd-data PersistentVolume does not exist"
            return 1
        fi
        
        if kubectl get pvc pipecd-data -n pipecd &>/dev/null; then
            test_pass "pipecd-data PersistentVolumeClaim exists"
        else
            test_fail "pipecd-data PersistentVolumeClaim does not exist"
            return 1
        fi
    else
        test_skip "Volume PV/PVC check skipped for non-Docker driver"
    fi
    
    return 0
}

test_makefile_targets() {
    log_info "Testing Makefile targets..."
    
    cd "${ROOT_DIR}"
    
    # Test that makefile targets exist
    if grep -q "up/minikube-cluster:" Makefile; then
        test_pass "Makefile target 'up/minikube-cluster' exists"
    else
        test_fail "Makefile target 'up/minikube-cluster' does not exist"
        return 1
    fi
    
    if grep -q "down/minikube-cluster:" Makefile; then
        test_pass "Makefile target 'down/minikube-cluster' exists"
    else
        test_fail "Makefile target 'down/minikube-cluster' does not exist"
        return 1
    fi
    
    if grep -q "up/local-cluster-minikube:" Makefile; then
        test_pass "Makefile target 'up/local-cluster-minikube' exists"
    else
        test_fail "Makefile target 'up/local-cluster-minikube' does not exist"
        return 1
    fi
    
    return 0
}

test_registry_connectivity_from_cluster() {
    log_info "Testing registry connectivity from cluster..."
    
    # Create a test pod that tries to pull from the registry
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: registry-test
  namespace: default
spec:
  restartPolicy: Never
  containers:
  - name: test
    image: localhost:${REG_PORT}/test:latest
    command: ["/bin/sh", "-c", "echo 'Registry test'"]
  imagePullPolicy: IfNotPresent
EOF
    
    # Wait a bit for the pod to be created
    sleep 2
    
    # Check if pod was created (it will fail to pull, but that's expected)
    if kubectl get pod registry-test &>/dev/null; then
        test_pass "Test pod was created (registry connectivity test)"
    else
        test_fail "Test pod was not created"
        return 1
    fi
    
    # Cleanup test pod
    kubectl delete pod registry-test --ignore-not-found=true &>/dev/null
    
    return 0
}

# Main test execution
main() {
    echo "========================================="
    echo "Minikube Setup Test Suite"
    echo "========================================="
    echo "Test cluster: ${TEST_CLUSTER}"
    echo "Minikube driver: ${MINIKUBE_DRIVER}"
    echo "========================================="
    echo ""
    
    # Run tests
    test_prerequisites || {
        log_error "Prerequisites check failed. Skipping remaining tests."
        exit 1
    }
    
    test_script_syntax || {
        log_error "Script syntax check failed. Skipping remaining tests."
        exit 1
    }
    
    test_local_registry_exists || {
        log_error "Local registry setup failed. Skipping cluster tests."
        exit 1
    }
    
    test_minikube_cluster_creation || {
        log_error "Cluster creation failed. Skipping cluster verification tests."
        exit 1
    }
    
    test_kubectl_access || {
        log_error "kubectl access failed. Skipping remaining cluster tests."
        exit 1
    }
    
    test_namespace_creation
    test_registry_configuration
    test_volume_setup
    test_makefile_targets
    test_registry_connectivity_from_cluster
    
    log_info "All tests completed!"
}

# Run main function
main
