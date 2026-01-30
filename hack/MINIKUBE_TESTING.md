# Minikube Setup Testing

This document describes the test-driven development (TDD) approach used to verify the Minikube local development setup for PipeCD.

## Test Scripts

### 1. `validate-minikube-script.sh` (Static Validation)

A lightweight validation script that performs static analysis without requiring Minikube to be installed.

**What it tests:**
- Script syntax validation
- Required variables and functions
- Error handling (errexit, nounset)
- Required command usage (minikube, docker, kubectl)
- Registry configuration logic
- Namespace creation logic
- Volume setup logic
- OS compatibility handling
- Copyright headers

**Usage:**
```bash
# Run validation
make validate/minikube-script

# Or directly
./hack/validate-minikube-script.sh
```

**When to use:**
- During development to catch syntax errors quickly
- In CI/CD pipelines where Minikube may not be available
- Before committing changes

### 2. `test-minikube-setup.sh` (Integration Tests)

A comprehensive integration test suite that verifies the complete Minikube setup end-to-end.

**What it tests:**
1. **Prerequisites**: Verifies minikube, docker, and kubectl are installed
2. **Script Syntax**: Validates bash syntax
3. **Local Registry**: Ensures registry container is running and accessible
4. **Cluster Creation**: Creates a test Minikube cluster
5. **kubectl Access**: Verifies cluster is accessible via kubectl
6. **Namespace Creation**: Confirms `pipecd` namespace exists
7. **Registry Configuration**: Validates containerd registry config and ConfigMap
8. **Volume Setup**: Checks Docker volume and PV/PVC creation
9. **Makefile Targets**: Verifies all Makefile targets exist
10. **Registry Connectivity**: Tests registry connectivity from within the cluster

**Usage:**
```bash
# Run full integration test suite
make test/minikube-setup

# Or directly
./hack/test-minikube-setup.sh

# With custom driver
MINIKUBE_DRIVER=docker ./hack/test-minikube-setup.sh
```

**Prerequisites:**
- Minikube installed and configured
- Docker installed and running
- kubectl installed
- Sufficient system resources for Minikube

**Test Environment:**
- Creates a temporary test cluster: `pipecd-test-<timestamp>`
- Automatically cleans up after tests complete
- Uses existing `kind-registry` container or creates one

## TDD Workflow

### 1. Write Tests First
```bash
# Start with validation
make validate/minikube-script
```

### 2. Implement/Modify Script
Edit `hack/create-minikube-cluster.sh` to make it pass the tests.

### 3. Run Validation
```bash
make validate/minikube-script
```

### 4. Run Integration Tests (if Minikube available)
```bash
make test/minikube-setup
```

### 5. Fix Issues
If tests fail, fix the script and re-run tests.

## Test Results

### Validation Script Output
```
=========================================
Minikube Script Validation
=========================================
[INFO] ✓ Script syntax is valid
[INFO] ✓ Variable 'CLUSTER' is used
[INFO] ✓ Script has 'set -o errexit'
...
=========================================
Validation Summary
=========================================
✓ All checks passed!
```

### Integration Test Output
```
=========================================
Minikube Setup Test Suite
=========================================
Test cluster: pipecd-test-1234567890
Minikube driver: docker
=========================================

[INFO] Testing prerequisites...
✓ PASS: minikube is installed
✓ PASS: docker is installed
...
=========================================
Test Summary
=========================================
Passed: 15
Failed: 0
Skipped: 0
=========================================
```

## Continuous Integration

For CI/CD pipelines:

1. **Always run validation** (fast, no dependencies):
   ```yaml
   - name: Validate Minikube script
     run: make validate/minikube-script
   ```

2. **Optionally run integration tests** (requires Minikube):
   ```yaml
   - name: Test Minikube setup
     run: make test/minikube-setup
     # Only if Minikube is available in CI environment
   ```

## Troubleshooting

### Validation fails
- Check script syntax: `bash -n hack/create-minikube-cluster.sh`
- Review error messages for specific issues

### Integration tests fail
- Ensure Minikube is installed: `minikube version`
- Ensure Docker is running: `docker info`
- Check Minikube status: `minikube status`
- Review test output for specific failure points
- Check cluster logs: `minikube logs -p <cluster-name>`

### Tests hang or timeout
- Check system resources (CPU, memory, disk)
- Verify Docker has sufficient resources allocated
- Try cleaning up existing clusters: `minikube delete --all`

## Adding New Tests

To add a new test case:

1. Add test function to `test-minikube-setup.sh`:
   ```bash
   test_new_feature() {
       log_info "Testing new feature..."
       # Your test logic here
       if <condition>; then
           test_pass "New feature works"
       else
           test_fail "New feature failed"
           return 1
       fi
   }
   ```

2. Call it in the `main()` function:
   ```bash
   test_new_feature
   ```

3. Update this documentation with the new test description.

## Best Practices

1. **Always run validation before committing**
2. **Run integration tests before opening PRs**
3. **Keep tests focused and independent**
4. **Clean up test resources properly**
5. **Document any test-specific requirements**
