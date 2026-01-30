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

# This script validates the Minikube setup script without requiring Minikube to be installed.
# It performs static analysis and basic validation checks.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/create-minikube-cluster.sh"

ERRORS=0
WARNINGS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ERRORS=$((ERRORS + 1))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo "========================================="
echo "Minikube Script Validation"
echo "========================================="
echo ""

# Test 1: Check if script exists
if [ ! -f "${SCRIPT}" ]; then
    log_error "Script not found: ${SCRIPT}"
    exit 1
fi
log_info "Script exists: ${SCRIPT}"

# Test 2: Check script syntax
log_info "Checking bash syntax..."
if bash -n "${SCRIPT}"; then
    log_info "✓ Script syntax is valid"
else
    log_error "Script has syntax errors"
    exit 1
fi

# Test 3: Check for required functions/variables
log_info "Checking for required variables..."
REQUIRED_VARS=("CLUSTER" "REG_NAME" "REG_PORT" "MINIKUBE_DRIVER")
for var in "${REQUIRED_VARS[@]}"; do
    if grep -q "\${${var}}" "${SCRIPT}" || grep -q "\$${var}" "${SCRIPT}"; then
        log_info "✓ Variable '${var}' is used"
    else
        log_warn "Variable '${var}' may not be used"
    fi
done

# Test 4: Check for error handling
log_info "Checking error handling..."
if grep -q "set -o errexit" "${SCRIPT}"; then
    log_info "✓ Script has 'set -o errexit'"
else
    log_warn "Script may not exit on errors"
fi

if grep -q "set -o nounset" "${SCRIPT}"; then
    log_info "✓ Script has 'set -o nounset'"
else
    log_warn "Script may not catch unset variables"
fi

# Test 5: Check for required commands
log_info "Checking for required command usage..."
REQUIRED_CMDS=("minikube" "docker" "kubectl")
for cmd in "${REQUIRED_CMDS[@]}"; do
    if grep -q "${cmd}" "${SCRIPT}"; then
        log_info "✓ Script uses '${cmd}'"
    else
        log_warn "Script may not use '${cmd}'"
    fi
done

# Test 6: Check for registry configuration
log_info "Checking registry configuration..."
if grep -q "containerd" "${SCRIPT}"; then
    log_info "✓ Script configures containerd"
else
    log_warn "Script may not configure containerd for registry"
fi

# Test 7: Check for namespace creation
log_info "Checking namespace creation..."
if grep -q "pipecd" "${SCRIPT}" && grep -q "namespace" "${SCRIPT}"; then
    log_info "✓ Script creates pipecd namespace"
else
    log_warn "Script may not create pipecd namespace"
fi

# Test 8: Check for volume setup
log_info "Checking volume setup..."
if grep -q "pipecd-data" "${SCRIPT}"; then
    log_info "✓ Script handles pipecd-data volume"
else
    log_warn "Script may not handle pipecd-data volume"
fi

# Test 9: Check for OS compatibility
log_info "Checking OS compatibility..."
if grep -q "OSTYPE" "${SCRIPT}" || grep -q "darwin\|linux" "${SCRIPT}"; then
    log_info "✓ Script handles OS differences"
else
    log_warn "Script may not handle OS differences"
fi

# Test 10: Check for proper cleanup/documentation
log_info "Checking script documentation..."
if grep -q "Copyright" "${SCRIPT}"; then
    log_info "✓ Script has copyright header"
else
    log_warn "Script may be missing copyright header"
fi

# Summary
echo ""
echo "========================================="
echo "Validation Summary"
echo "========================================="
if [ ${ERRORS} -eq 0 ] && [ ${WARNINGS} -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    exit 0
elif [ ${ERRORS} -eq 0 ]; then
    echo -e "${YELLOW}⚠ Validation passed with ${WARNINGS} warning(s)${NC}"
    exit 0
else
    echo -e "${RED}✗ Validation failed with ${ERRORS} error(s) and ${WARNINGS} warning(s)${NC}"
    exit 1
fi
