Switch to [English](README_EN.md)

# MPU - 容器内 nvidia-smi 进程列表显示修复模块

一个 Linux 内核 shim 驱动程序，使 Docker 容器内的 `nvidia-smi` 能够正确显示进程列表，无需修改容器配置或使用宿主机 PID 命名空间。

## 📋 目录

- [项目背景](#项目背景)
- [问题描述](#问题描述)
- [传统解决方案](#传统解决方案)
- [MPU 解决方案](#mpu-解决方案)
- [工作原理](#工作原理)
- [系统要求](#系统要求)
- [编译安装](#编译安装)
- [功能测试](#功能测试)
- [卸载方法](#卸载方法)
- [已测试环境](#已测试环境)
- [Kubernetes 部署](#kubernetes-部署)
- [注意事项](#注意事项)
- [项目维护](#项目维护)

---

## 🎯 项目背景

当在 Docker 容器中运行 GPU 加速应用时，开发者和运维人员经常需要使用 `nvidia-smi` 命令来监控 GPU 使用情况。然而，由于 Linux 内核的 PID 命名空间隔离机制，容器内执行 `nvidia-smi` 时无法显示正在使用 GPU 的进程列表，这给调试和监控带来了极大的不便。

## 🔍 问题描述

### 核心问题

NVIDIA 驱动程序运行在宿主机的全局 PID 命名空间（`init_pid_ns`）中，它只能识别全局 PID。而 Docker 容器运行在独立的 PID 命名空间中，容器内的进程 PID 与宿主机上的全局 PID 不同。

### 技术原因

1. **PID 命名空间隔离**：Linux 内核通过 PID 命名空间实现容器隔离，容器内的进程有自己的 PID 编号
2. **驱动程序限制**：NVIDIA 驱动程序不感知 PID 命名空间，只能返回全局 PID
3. **nvidia-smi 限制**：nvidia-smi 工具无法将全局 PID 映射到容器内的虚拟 PID
4. **闭源困境**：NVIDIA 驱动程序是专有闭源软件，即使有部分开源代码也难以修改其核心功能

### 实际影响

在容器内执行 `nvidia-smi` 时：
- ✅ 可以看到 GPU 硬件信息
- ✅ 可以看到 GPU 利用率、显存使用等
- ❌ **无法看到正在使用 GPU 的进程列表**
- ❌ 无法知道哪个进程占用了多少显存

## 🔧 传统解决方案

### 方案一：使用宿主机 PID 命名空间

**Docker 方式：**
```bash
docker run --pid=host --gpus all your-image
```

**Kubernetes 方式：**
```yaml
spec:
  hostPID: true
```

**缺点：**
- ⚠️ 破坏了容器隔离性
- ⚠️ 容器可以看到宿主机上的所有进程
- ⚠️ 存在安全风险
- ⚠️ 违背了容器化的初衷

### 方案二：使用外部监控工具

从宿主机监控 GPU 使用情况，通过其他方式传递给容器。

**缺点：**
- ⚠️ 需要额外的监控基础设施
- ⚠️ 增加了系统复杂度
- ⚠️ 无法在容器内直接使用 nvidia-smi

## ✨ MPU 解决方案

MPU（Matpool Unit）提供了一个优雅的解决方案：

### 核心优势

- ✅ **无需修改容器配置**：不需要 `--pid=host` 或 `hostPID: true`
- ✅ **保持容器隔离性**：完整的 PID 命名空间隔离
- ✅ **透明工作**：对应用程序完全透明，无需修改代码
- ✅ **系统级方案**：在内核层面解决问题，适用于所有容器
- ✅ **安全性**：不破坏容器安全边界

### 应用场景

- 🐳 Docker 容器中的 GPU 应用开发和调试
- ☸️ Kubernetes 集群中的 GPU 任务监控
- 🔬 机器学习/深度学习训练任务监控
- 🎮 GPU 计算集群管理
- 📊 多租户 GPU 资源监控

## ⚙️ 工作原理

MPU 通过内核模块的方式，在系统调用层面进行拦截和转换。

### 技术流程

1. **系统调用拦截**
   - 使用 ftrace 框架在系统级别拦截 ioctl 系统调用
   - 只拦截 NVIDIA 设备的 ioctl 调用（设备主设备号 195，次设备号 255）

2. **PID 命名空间检测**
   - 检测调用进程是否运行在独立的 PID 命名空间中
   - 如果在全局命名空间（宿主机），直接透传，不做处理

3. **双向 PID 转换**
   - **阶段一（获取进程列表）**：将 NVIDIA 驱动返回的全局 PID 列表转换为容器内的虚拟 PID
   - **阶段二（查询进程信息）**：
     - 预处理：将容器内的虚拟 PID 转回全局 PID，让驱动能识别
     - 后处理：将驱动返回的结果中的全局 PID 再转换为虚拟 PID

4. **透明返回**
   - 将转换后的数据返回给 nvidia-smi
   - nvidia-smi 看到的是容器内的 PID，可以正确显示进程列表

### 技术特点

- 🔐 使用内核标准的 ftrace 和 kprobe 机制
- 🎯 精确识别 NVIDIA 特定的 ioctl 命令（0xee4 和 0x1f48）
- 🔄 实时双向 PID 映射
- 🚀 性能开销极小，不影响 GPU 计算性能
- 🛡️ 不修改 NVIDIA 驱动，保持驱动完整性

## 💻 系统要求

### 必需依赖

- **操作系统**：Linux（建议使用 Ubuntu/Debian）
- **内核版本**：≥ 5.4（已测试到 6.14）
- **内核头文件**：对应当前运行内核版本
- **编译工具**：build-essential（包含 gcc、make 等）
- **NVIDIA 驱动**：已安装并正常工作
- **Docker/容器运行时**：支持 GPU 的容器运行时

### 内核版本说明

⚠️ **重要提示**：Kernel 5.7.7 之后，内核构建过程不再导出 kallsyms 函数，MPU 使用 kprobe 机制作为替代方案。大多数现代内核都能正常工作。

## 🔨 编译安装

### 第一步：安装依赖

```bash
# 安装内核头文件（必须与运行的内核版本匹配）
sudo apt install linux-headers-$(uname -r)

# 安装编译工具链
sudo apt-get install build-essential
```

### 第二步：获取源码

```bash
# 克隆仓库
git clone https://github.com/lengrongfu/mpu.git
cd mpu
```

### 第三步：编译模块

```bash
# 编译内核模块
make

# 编译成功后会生成 mpu.ko 文件
ls -lh mpu.ko
```

### 第四步：安装模块

**方式 A：临时加载（重启后失效）**

```bash
# 加载模块
sudo insmod mpu.ko

# 验证加载
lsmod | grep mpu
```

**方式 B：持久化安装（推荐）**

```bash
# 1. 复制模块到系统目录
sudo mkdir -p /lib/modules/$(uname -r)/extra/
sudo cp mpu.ko /lib/modules/$(uname -r)/extra/

# 2. 更新模块依赖关系
sudo depmod -a

# 3. 配置开机自动加载
echo "mpu" | sudo tee /etc/modules-load.d/mpu.conf

# 4. 加载模块
sudo modprobe mpu

# 5. 验证
lsmod | grep mpu
modinfo mpu | grep filename
```

**期望输出：**
```
filename:       /lib/modules/6.14.0-33-generic/extra/mpu.ko
```

如果 filename 显示的是系统目录路径（而非项目目录），说明安装成功，之后可以安全删除项目源码目录。

### 验证模块加载

```bash
# 检查模块是否加载
lsmod | grep mpu

# 查看内核日志
sudo dmesg | grep -i mpu | tail -10

# 查看模块信息
modinfo mpu
```

## 🧪 功能测试

### 基础测试

```bash
# 创建一个启用 GPU 的 Docker 容器
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi

# 或者使用其他 CUDA 镜像
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

### 运行 GPU 程序测试

```bash
# 在容器内运行一个使用 GPU 的程序
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 bash -c "
  apt-get update && apt-get install -y cuda-samples-12-0
  cd /usr/local/cuda/samples/1_Utilities/deviceQuery
  make && ./deviceQuery &
  sleep 2
  nvidia-smi
"
```

### 期望结果

安装 MPU 后，`nvidia-smi` 输出应该包含类似以下的进程列表：

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

其中 PID 应该是容器内的进程 ID，而不是空的。

## 🗑️ 卸载方法

### 临时卸载（不影响下次开机）

```bash
# 卸载当前加载的模块
sudo rmmod mpu

# 验证
lsmod | grep mpu  # 应该没有输出
```

### 完全卸载

```bash
# 1. 卸载模块
sudo rmmod mpu

# 2. 删除自动加载配置
sudo rm /etc/modules-load.d/mpu.conf

# 3. 删除系统模块文件
sudo rm /lib/modules/$(uname -r)/extra/mpu.ko

# 4. 更新模块依赖
sudo depmod -a

# 5. 验证
modprobe -n mpu  # 应该显示模块不存在
```

## ✅ 已测试环境

MPU 已在以下环境中经过完整测试，确认可以正常工作：

| 操作系统 | 内核版本 | Docker 版本 | NVIDIA 驱动 | 状态 |
|---------|---------|------------|------------|------|
| Ubuntu 20.04 | 5.4.0-153 | 28.0.1 | 535.171.04 | ✅ |
| Ubuntu 20.04 | 5.4.0-208 | 28.0.1 | 550.135 | ✅ |
| Ubuntu 22.04 | 5.15.0-125 | 27.5.0 | 550.135 | ✅ |
| Ubuntu 22.04 | 5.15.0-134 | 28.0.1 | 550.135 | ✅ |
| Ubuntu 24.04 | 6.8.0-55 | 28.0.1 | 550.135 | ✅ |
| Ubuntu 24.04 | 6.8.0-55 | 28.0.1 | 570.124.04 | ✅ |
| **Ubuntu 24.04** | **6.14.0-33** | **28.5.1** | **580.95.05** | ✅ |

> **最新更新**：已完成对 Kernel 6.14 的适配，修复了新内核中 `struct fd` API 变化的兼容性问题。

### 内核版本兼容性

- ✅ **Kernel 5.4 - 5.6**：完全支持
- ✅ **Kernel 5.7+**：使用 kprobe 机制，完全支持
- ✅ **Kernel 6.8**：完全支持
- ✅ **Kernel 6.10+**：适配新的 `fd_file()` API，完全支持
- ✅ **Kernel 6.14**：最新测试，完全支持

## ☸️ Kubernetes 部署

MPU 支持通过 Helm Chart 部署到 Kubernetes 集群，自动在所有 GPU 节点上安装。

```bash
# 使用 Helm 安装
helm install mpu oci://ghcr.io/lengrongfu/mpu --version 0.0.1
```

部署后，集群中所有 Pod 都能在容器内正确使用 `nvidia-smi` 查看进程列表。

## ⚠️ 注意事项

### 安全启动（Secure Boot）

如果系统启用了 Secure Boot，内核模块需要签名才能加载。解决方案：

1. **禁用 Secure Boot**（最简单）
2. **签名内核模块**（推荐用于生产环境）

### 内核更新

系统内核更新后，需要重新编译和安装 MPU 模块：

```bash
# 内核更新后
cd /path/to/mpu
make clean
make
sudo cp mpu.ko /lib/modules/$(uname -r)/extra/
sudo depmod -a
sudo modprobe mpu
```

### 性能影响

MPU 的性能开销极小：
- ✅ 只拦截 NVIDIA 设备的 ioctl 调用
- ✅ 只在查询进程信息时进行转换
- ✅ 不影响 GPU 计算性能
- ✅ 对宿主机进程完全透明

### 故障排查

如果模块无法加载，检查以下几点：

```bash
# 1. 检查内核日志
sudo dmesg | grep -i mpu

# 2. 检查内核版本和头文件是否匹配
uname -r
dpkg -l | grep linux-headers

# 3. 检查 NVIDIA 驱动状态
nvidia-smi

# 4. 检查模块签名问题
mokutil --sb-state  # 查看 Secure Boot 状态

# 5. 尝试手动加载并查看详细错误
sudo insmod mpu.ko
```

## 🤝 项目维护

### 开发团队

- **作者**：Magnus <Magnusbackyard@live.com>
- **版本**：0.1-pre
- **许可证**：GPL v2

### 项目目标

我们致力于维护此项目，持续测试更多内核版本和 NVIDIA 驱动组合，确保广泛的兼容性。

### 寄语

我们衷心希望 NVIDIA 能够在未来的驱动版本中原生支持 PID 命名空间，以更简洁和专业的方式解决这个问题。在那之前，MPU 将继续为社区提供可靠的解决方案。

### 贡献

欢迎提交问题报告、功能请求和代码贡献。

---

## 📚 延伸阅读

### 相关技术

- Linux PID 命名空间
- Linux 内核 ftrace 框架
- NVIDIA GPU 驱动架构
- Docker 容器隔离机制
- ioctl 系统调用机制

### 技术图解

项目包含详细的技术架构图，展示 PID 转换的完整流程。

---

**项目地址**：https://github.com/lengrongfu/mpu

**问题反馈**：https://github.com/lengrongfu/mpu/issues

**最后更新**：2025-12-10
