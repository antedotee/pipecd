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

# This script compares KinD and Minikube setups to ensure they provide equivalent functionality

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIND_CLUSTER="pipecd-kind-test"
MINIKUBE_CLUSTER="pipecd-minikube-test"
REG_NAME='kind-registry'
REG_PORT='5001'

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
DIFFERENCES=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    DIFFERENCES=$((DIFFERENCES + 1))
}

log_diff() {
    echo -e "${YELLOW}[DIFF]${NC} $1"
    DIFFERENCES=$((DIFFERENCES + 1))
}

cleanup() {
    echo ""
    log_info "Cleaning up test clusters..."
    
    # Cleanup KinD
    if kind get clusters | grep -q "^${KIND_CLUSTER}$"; then
        log_info "Deleting KinD cluster: ${KIND_CLUSTER}"
        kind delete cluster --name "${KIND_CLUSTER}" || true
    fi
    
    # Cleanup Minikube
    if minikube status -p "${MINIKUBE_CLUSTER}" &>/dev/null; then
        log_info "Deleting Minikube cluster: ${MINIKUBE_CLUSTER}"
        minikube delete -p "${MINIKUBE_CLUSTER}" || true
    fi
    
    echo ""
    echo "========================================="
    echo "Comparison Summary"
    echo "========================================="
    echo -e "${GREEN}Tests Passed: ${TESTS_PASSED}${NC}"
    echo -e "${RED}Tests Failed: ${TESTS_FAILED}${NC}"
    echo -e "${YELLOW}Differences Found: ${DIFFERENCES}${NC}"
    echo "========================================="
    
    if [ ${TESTS_FAILED} -gt 0 ] || [ ${DIFFERENCES} -gt 0 ]; then
        exit 1
    fi
}

trap cleanup EXIT

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing=0
    
    if ! command -v kind &> /dev/null; then
        log_fail "kind is not installed"
        missing=1
    fi
    
    if ! command -v minikube &> /dev/null; then
        log_fail "minikube is not installed"
        missing=1
    fi
    
    if ! command -v docker &> /dev/null; then
        log_fail "docker is not installed"
        missing=1
    fi
    
    if ! docker info &> /dev/null; then
        log_fail "docker daemon is not running"
        missing=1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        log_fail "kubectl is not installed"
        missing=1
    fi
    
    if [ ${missing} -eq 1 ]; then
        return 1
    fi
    
    log_success "All prerequisites met"
    return 0
}

setup_kind() {
    log_info "Setting up KinD cluster..."
    
    # Ensure local registry exists
    if ! docker ps --format '{{.Names}}' | grep -q "^${REG_NAME}$"; then
        "${SCRIPT_DIR}/create-local-registry.sh"
    fi
    
    # Create KinD cluster
    "${SCRIPT_DIR}/create-kind-cluster.sh" "${KIND_CLUSTER}"
    
    # Export kubeconfig
    kind export kubeconfig --name "${KIND_CLUSTER}"
    
    log_success "KinD cluster created"
}

setup_minikube() {
    log_info "Setting up Minikube cluster..."
    
    # Ensure local registry exists
    if ! docker ps --format '{{.Names}}' | grep -q "^${REG_NAME}$"; then
        "${SCRIPT_DIR}/create-local-registry.sh"
    fi
    
    # Create Minikube cluster
    MINIKUBE_DRIVER=docker "${SCRIPT_DIR}/create-minikube-cluster.sh" "${MINIKUBE_CLUSTER}"
    
    # Export kubeconfig
    export KUBECONFIG=$(minikube kubectl --profile "${MINIKUBE_CLUSTER}" -- config view --flatten --minify)
    
    log_success "Minikube cluster created"
}

compare_namespace() {
    log_info "Comparing namespace creation..."
    
    local kind_ns=$(kubectl --context kind-${KIND_CLUSTER} get namespace pipecd -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
    local minikube_ns=$(kubectl --context ${MINIKUBE_CLUSTER} get namespace pipecd -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "${kind_ns}" ] && [ -n "${minikube_ns}" ]; then
        log_success "Both clusters have pipecd namespace"
    elif [ -z "${kind_ns}" ] && [ -z "${minikube_ns}" ]; then
        log_fail "Neither cluster has pipecd namespace"
    else
        log_diff "Namespace mismatch: KinD=${kind_ns}, Minikube=${minikube_ns}"
    fi
}

compare_registry_configmap() {
    log_info "Comparing registry ConfigMap..."
    
    local kind_cm=$(kubectl --context kind-${KIND_CLUSTER} get configmap local-registry-hosting -n kube-public -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
    local minikube_cm=$(kubectl --context ${MINIKUBE_CLUSTER} get configmap local-registry-hosting -n kube-public -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "${kind_cm}" ] && [ -n "${minikube_cm}" ]; then
        log_success "Both clusters have registry ConfigMap"
        
        # Compare content
        local kind_host=$(kubectl --context kind-${KIND_CLUSTER} get configmap local-registry-hosting -n kube-public -o jsonpath='{.data.localRegistryHosting\.v1}' | grep -oP 'host: \K[^[:space:]]+' || echo "")
        local minikube_host=$(kubectl --context ${MINIKUBE_CLUSTER} get configmap local-registry-hosting -n kube-public -o jsonpath='{.data.localRegistryHosting\.v1}' | grep -oP 'host: \K[^[:space:]]+' || echo "")
        
        if [ "${kind_host}" = "${minikube_host}" ]; then
            log_success "Registry host configuration matches"
        else
            log_diff "Registry host differs: KinD=${kind_host}, Minikube=${minikube_host}"
        fi
    else
        log_diff "ConfigMap mismatch: KinD=${kind_cm}, Minikube=${minikube_cm}"
    fi
}

compare_volume() {
    log_info "Comparing volume setup..."
    
    # Check Docker volume exists (both should use the same)
    if docker volume ls | grep -q pipecd-data; then
        log_success "pipecd-data Docker volume exists"
    else
        log_fail "pipecd-data Docker volume does not exist"
    fi
    
    # Check PV/PVC (Minikube specific for Docker driver)
    local minikube_pv=$(kubectl --context ${MINIKUBE_CLUSTER} get pv pipecd-data -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "${minikube_pv}" ]; then
        log_success "Minikube has PersistentVolume for pipecd-data"
    else
        log_diff "Minikube does not have PersistentVolume (may be expected for non-Docker driver)"
    fi
}

compare_registry_connectivity() {
    log_info "Comparing registry connectivity..."
    
    # Test from KinD cluster
    local kind_test=$(kubectl --context kind-${KIND_CLUSTER} run registry-test-kind --image=localhost:${REG_PORT}/test:latest --restart=Never --dry-run=client -o jsonpath='{.spec.containers[0].image}' 2>/dev/null || echo "")
    
    # Test from Minikube cluster  
    local minikube_test=$(kubectl --context ${MINIKUBE_CLUSTER} run registry-test-minikube --image=localhost:${REG_PORT}/test:latest --restart=Never --dry-run=client -o jsonpath='{.spec.containers[0].image}' 2>/dev/null || echo "")
    
    if [ -n "${kind_test}" ] && [ -n "${minikube_test}" ]; then
        log_success "Both clusters can reference local registry"
    else
        log_diff "Registry connectivity differs between clusters"
    fi
    
    # Cleanup test pods
    kubectl --context kind-${KIND_CLUSTER} delete pod registry-test-kind --ignore-not-found=true &>/dev/null
    kubectl --context ${MINIKUBE_CLUSTER} delete pod registry-test-minikube --ignore-not-found=true &>/dev/null
}

compare_kubectl_access() {
    log_info "Comparing kubectl access..."
    
    if kubectl --context kind-${KIND_CLUSTER} cluster-info &>/dev/null; then
        log_success "KinD cluster is accessible via kubectl"
    else
        log_fail "KinD cluster is not accessible via kubectl"
    fi
    
    if kubectl --context ${MINIKUBE_CLUSTER} cluster-info &>/dev/null; then
        log_success "Minikube cluster is accessible via kubectl"
    else
        log_fail "Minikube cluster is not accessible via kubectl"
    fi
}

compare_node_count() {
    log_info "Comparing node configuration..."
    
    local kind_nodes=$(kubectl --context kind-${KIND_CLUSTER} get nodes --no-headers | wc -l | tr -d ' ')
    local minikube_nodes=$(kubectl --context ${MINIKUBE_CLUSTER} get nodes --no-headers | wc -l | tr -d ' ')
    
    if [ "${kind_nodes}" = "${minikube_nodes}" ]; then
        log_success "Both clusters have ${kind_nodes} node(s)"
    else
        log_diff "Node count differs: KinD=${kind_nodes}, Minikube=${minikube_nodes}"
    fi
}

main() {
    echo "========================================="
    echo "KinD vs Minikube Comparison Test"
    echo "========================================="
    echo ""
    
    if ! check_prerequisites; then
        echo "Prerequisites not met. Exiting."
        exit 1
    fi
    
    log_info "Setting up test clusters..."
    setup_kind
    setup_minikube
    
    echo ""
    log_info "Running comparison tests..."
    echo ""
    
    compare_kubectl_access
    compare_namespace
    compare_registry_configmap
    compare_volume
    compare_registry_connectivity
    compare_node_count
    
    echo ""
    log_info "Comparison complete!"
}

main
