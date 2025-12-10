切换到[中文](README.md)

# MPU - nvidia-smi Process List Fix for Containers

A Linux kernel shim driver that enables `nvidia-smi` inside Docker containers to correctly display process lists without modifying container configurations or using host PID namespace.

## 📋 Table of Contents

- [Background](#background)
- [Problem Description](#problem-description)
- [Traditional Solutions](#traditional-solutions)
- [MPU Solution](#mpu-solution)
- [How It Works](#how-it-works)
- [System Requirements](#system-requirements)
- [Build and Install](#build-and-install)
- [Testing](#testing)
- [Uninstallation](#uninstallation)
- [Tested Environments](#tested-environments)
- [Kubernetes Deployment](#kubernetes-deployment)
- [Important Notes](#important-notes)
- [Project Maintenance](#project-maintenance)

---

## 🎯 Background

When running GPU-accelerated applications in Docker containers, developers and operators frequently need to use the `nvidia-smi` command to monitor GPU usage. However, due to Linux kernel's PID namespace isolation mechanism, executing `nvidia-smi` inside containers cannot display the list of processes using the GPU, causing significant inconvenience for debugging and monitoring.

## 🔍 Problem Description

### Core Issue

The NVIDIA driver runs in the host's global PID namespace (`init_pid_ns`) and can only recognize global PIDs. Docker containers run in separate PID namespaces where process PIDs differ from the host's global PIDs.

### Technical Reasons

1. **PID Namespace Isolation**: Linux kernel implements container isolation through PID namespaces
2. **Driver Limitations**: NVIDIA driver is not aware of PID namespaces and only returns global PIDs
3. **nvidia-smi Limitations**: nvidia-smi cannot map global PIDs to container virtual PIDs
4. **Proprietary Constraints**: NVIDIA driver is proprietary closed-source software, making modifications difficult

### Real-world Impact

When executing `nvidia-smi` inside containers:
- ✅ GPU hardware information is visible
- ✅ GPU utilization and memory usage are shown
- ❌ **Process list using GPU is not displayed**
- ❌ Cannot identify which process occupies how much memory

## 🔧 Traditional Solutions

### Solution 1: Use Host PID Namespace

**Docker:**
```bash
docker run --pid=host --gpus all your-image
```

**Kubernetes:**
```yaml
spec:
  hostPID: true
```

**Drawbacks:**
- ⚠️ Breaks container isolation
- ⚠️ Container can see all host processes
- ⚠️ Security risks
- ⚠️ Defeats the purpose of containerization

### Solution 2: External Monitoring Tools

Monitor GPU usage from the host and relay information to containers.

**Drawbacks:**
- ⚠️ Requires additional monitoring infrastructure
- ⚠️ Increases system complexity
- ⚠️ Cannot use nvidia-smi directly inside containers

## ✨ MPU Solution

MPU (Matpool Unit) provides an elegant solution:

### Core Advantages

- ✅ **No container configuration changes**: No need for `--pid=host` or `hostPID: true`
- ✅ **Maintains container isolation**: Full PID namespace isolation
- ✅ **Transparent operation**: Completely transparent to applications
- ✅ **System-wide solution**: Kernel-level fix applicable to all containers
- ✅ **Security**: Doesn't break container security boundaries

### Use Cases

- 🐳 GPU application development and debugging in Docker containers
- ☸️ GPU task monitoring in Kubernetes clusters
- 🔬 Machine learning/deep learning training job monitoring
- 🎮 GPU compute cluster management
- 📊 Multi-tenant GPU resource monitoring

## ⚙️ How It Works

MPU intercepts and transforms PIDs at the system call level through a kernel module.

### Technical Flow

1. **System Call Interception**
   - Uses ftrace framework to intercept ioctl system calls at system level
   - Only intercepts NVIDIA device ioctl calls (major device number 195, minor 255)

2. **PID Namespace Detection**
   - Detects if calling process runs in a separate PID namespace
   - If in global namespace (host), passes through without processing

3. **Bidirectional PID Translation**
   - **Stage 1 (Get Process List)**: Converts global PIDs from NVIDIA driver to container virtual PIDs
   - **Stage 2 (Query Process Info)**:
     - Pre-processing: Converts container virtual PIDs back to global PIDs for driver recognition
     - Post-processing: Converts global PIDs in driver response back to virtual PIDs

4. **Transparent Return**
   - Returns translated data to nvidia-smi
   - nvidia-smi sees container PIDs and displays process list correctly

### Technical Features

- 🔐 Uses kernel standard ftrace and kprobe mechanisms
- 🎯 Precisely identifies NVIDIA-specific ioctl commands (0xee4 and 0x1f48)
- 🔄 Real-time bidirectional PID mapping
- 🚀 Minimal performance overhead, doesn't affect GPU compute performance
- 🛡️ Doesn't modify NVIDIA driver, maintains driver integrity

## 💻 System Requirements

### Required Dependencies

- **Operating System**: Linux (Ubuntu/Debian recommended)
- **Kernel Version**: ≥ 5.4 (tested up to 6.14)
- **Kernel Headers**: Matching current running kernel version
- **Build Tools**: build-essential (includes gcc, make, etc.)
- **NVIDIA Driver**: Installed and working
- **Docker/Container Runtime**: GPU-capable container runtime

### Kernel Version Notes

⚠️ **Important**: After Kernel 5.7.7, kernel build routines don't export kallsyms functions. MPU uses kprobe mechanism as an alternative. Most modern kernels work properly.

## 🔨 Build and Install

### Step 1: Install Dependencies

```bash
# Install kernel headers (must match running kernel version)
sudo apt install linux-headers-$(uname -r)

# Install build toolchain
sudo apt-get install build-essential
```

### Step 2: Get Source Code

```bash
# Clone repository
git clone https://github.com/lengrongfu/mpu.git
cd mpu
```

### Step 3: Build Module

```bash
# Build kernel module
make

# Verify mpu.ko is generated
ls -lh mpu.ko
```

### Step 4: Install Module

**Option A: Temporary Load (doesn't persist after reboot)**

```bash
# Load module
sudo insmod mpu.ko

# Verify loading
lsmod | grep mpu
```

**Option B: Persistent Installation (Recommended)**

```bash
# 1. Copy module to system directory
sudo mkdir -p /lib/modules/$(uname -r)/extra/
sudo cp mpu.ko /lib/modules/$(uname -r)/extra/

# 2. Update module dependencies
sudo depmod -a

# 3. Configure auto-load on boot
echo "mpu" | sudo tee /etc/modules-load.d/mpu.conf

# 4. Load module
sudo modprobe mpu

# 5. Verify
lsmod | grep mpu
modinfo mpu | grep filename
```

**Expected output:**
```
filename:       /lib/modules/6.14.0-33-generic/extra/mpu.ko
```

If filename shows system directory path (not project directory), installation is successful and project source directory can be safely deleted.

### Verify Module Loading

```bash
# Check if module is loaded
lsmod | grep mpu

# View kernel logs
sudo dmesg | grep -i mpu | tail -10

# View module information
modinfo mpu
```

## 🧪 Testing

### Basic Test

```bash
# Create GPU-enabled Docker container
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi

# Or use other CUDA images
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

### GPU Program Test

```bash
# Run GPU program inside container
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 bash -c "
  apt-get update && apt-get install -y cuda-samples-12-0
  cd /usr/local/cuda/samples/1_Utilities/deviceQuery
  make && ./deviceQuery &
  sleep 2
  nvidia-smi
"
```

### Expected Result

After installing MPU, `nvidia-smi` output should include process list similar to:

```
+-----------------------------------------------------------------------------+
| Processes:                                                                  |
|  GPU   GI   CI        PID   Type   Process name                  GPU Memory |
|        ID   ID                                                   Usage      |
|=============================================================================|
|    0   N/A  N/A      1234    C   python3                            2048MiB |
|    0   N/A  N/A      5678    C   ./deviceQuery                        256MiB |
+-----------------------------------------------------------------------------+
```

PIDs should be container process IDs, not empty.

## 🗑️ Uninstallation

### Temporary Unload (doesn't affect next boot)

```bash
# Unload module
sudo rmmod mpu

# Verify
lsmod | grep mpu  # should have no output
```

### Complete Uninstallation

```bash
# 1. Unload module
sudo rmmod mpu

# 2. Remove auto-load configuration
sudo rm /etc/modules-load.d/mpu.conf

# 3. Remove system module file
sudo rm /lib/modules/$(uname -r)/extra/mpu.ko

# 4. Update module dependencies
sudo depmod -a

# 5. Verify
modprobe -n mpu  # should show module doesn't exist
```

## ✅ Tested Environments

MPU has been thoroughly tested in the following environments and confirmed working:

| OS | Kernel | Docker | NVIDIA Driver | Status |
|---------|---------|------------|------------|------|
| Ubuntu 20.04 | 5.4.0-153 | 28.0.1 | 535.171.04 | ✅ |
| Ubuntu 20.04 | 5.4.0-208 | 28.0.1 | 550.135 | ✅ |
| Ubuntu 22.04 | 5.15.0-125 | 27.5.0 | 550.135 | ✅ |
| Ubuntu 22.04 | 5.15.0-134 | 28.0.1 | 550.135 | ✅ |
| Ubuntu 24.04 | 6.8.0-55 | 28.0.1 | 550.135 | ✅ |
| Ubuntu 24.04 | 6.8.0-55 | 28.0.1 | 570.124.04 | ✅ |
| **Ubuntu 24.04** | **6.14.0-33** | **28.5.1** | **580.95.05** | ✅ |

> **Latest Update**: Completed Kernel 6.14 adaptation, fixed compatibility issues with `struct fd` API changes in new kernels.

### Kernel Version Compatibility

- ✅ **Kernel 5.4 - 5.6**: Fully supported
- ✅ **Kernel 5.7+**: Uses kprobe mechanism, fully supported
- ✅ **Kernel 6.8**: Fully supported
- ✅ **Kernel 6.10+**: Adapted to new `fd_file()` API, fully supported
- ✅ **Kernel 6.14**: Latest tested, fully supported

## ☸️ Kubernetes Deployment

MPU supports deployment to Kubernetes clusters via Helm Chart, automatically installing on all GPU nodes.

```bash
# Install using Helm
helm install mpu oci://ghcr.io/lengrongfu/mpu --version 0.0.1
```

After deployment, all pods in the cluster can correctly use `nvidia-smi` to view process lists inside containers.

## ⚠️ Important Notes

### Secure Boot

If system has Secure Boot enabled, kernel modules need signing to load. Solutions:

1. **Disable Secure Boot** (simplest)
2. **Sign kernel module** (recommended for production)

### Kernel Updates

After system kernel updates, MPU module needs to be recompiled and reinstalled:

```bash
# After kernel update
cd /path/to/mpu
make clean
make
sudo cp mpu.ko /lib/modules/$(uname -r)/extra/
sudo depmod -a
sudo modprobe mpu
```

### Performance Impact

MPU has minimal performance overhead:
- ✅ Only intercepts NVIDIA device ioctl calls
- ✅ Only performs translation when querying process information
- ✅ Doesn't affect GPU compute performance
- ✅ Completely transparent to host processes

### Troubleshooting

If module fails to load, check the following:

```bash
# 1. Check kernel logs
sudo dmesg | grep -i mpu

# 2. Verify kernel version and headers match
uname -r
dpkg -l | grep linux-headers

# 3. Check NVIDIA driver status
nvidia-smi

# 4. Check module signing issues
mokutil --sb-state  # Check Secure Boot status

# 5. Try manual load and view detailed errors
sudo insmod mpu.ko
```

## 🤝 Project Maintenance

### Development Team

- **Author**: Magnus <Magnusbackyard@live.com>
- **Version**: 0.1-pre
- **License**: GPL v2

### Project Goals

We are committed to maintaining this project, continuously testing more kernel versions and NVIDIA driver combinations to ensure broad compatibility.

### Message

We sincerely hope NVIDIA will natively support PID namespaces in future driver versions, solving this issue in a simpler and more professional way. Until then, MPU will continue providing reliable solutions for the community.

### Contributing

Welcome to submit issue reports, feature requests, and code contributions.

---

## 📚 Further Reading

### Related Technologies

- Linux PID namespaces
- Linux kernel ftrace framework
- NVIDIA GPU driver architecture
- Docker container isolation mechanisms
- ioctl system call mechanism

### Technical Diagrams

The project includes detailed technical architecture diagrams showing the complete PID translation flow.

---

**Project URL**: https://github.com/lengrongfu/mpu

**Issue Reports**: https://github.com/lengrongfu/mpu/issues

**Last Updated**: 2025-12-10

