#!/bin/bash
# MPU 模块完整安装脚本
# 自动清理旧配置，兼容 make install

set -e  # 遇到错误立即退出

echo "========================================="
echo "MPU 模块安装脚本"
echo "========================================="
echo ""

# 检查是否在项目目录（通过 Makefile 判断）
if [ ! -f "Makefile" ]; then
    echo "❌ 错误：找不到 Makefile"
    echo "请确保在项目目录中运行此脚本"
    exit 1
fi

# 检查 mpu.ko 是否存在，不存在则自动编译
if [ ! -f "mpu.ko" ]; then
    echo "⚠️  未找到 mpu.ko 文件"
    echo ""
    echo "步骤 0/7: 编译内核模块"
    echo "--------------------"
    echo "正在编译..."
    
    if make; then
        echo "✅ 编译成功"
    else
        echo "❌ 编译失败"
        echo ""
        echo "可能的原因："
        echo "1. 缺少内核头文件：sudo apt install linux-headers-\$(uname -r)"
        echo "2. 缺少编译工具：sudo apt-get install build-essential"
        echo "3. 内核版本不兼容"
        echo ""
        echo "请查看错误信息并解决后重试"
        exit 1
    fi
    echo ""
else
    echo "✅ 找到已编译的 mpu.ko 文件"
    echo ""
fi

# 检查是否有 sudo 权限
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

echo "步骤 1/7: 清理旧配置"
echo "--------------------"

# 卸载当前加载的模块（如果有）
if lsmod | grep -q "^mpu "; then
    echo "检测到已加载的 mpu 模块，正在卸载..."
    $SUDO rmmod mpu 2>/dev/null || true
    echo "✅ 模块已卸载"
else
    echo "ℹ️  未检测到已加载的模块"
fi

# ⭐ 关键：删除 make install 创建的旧配置文件
if [ -f "/etc/modules-load.d/matpool-mpu.conf" ]; then
    echo "发现 make install 的旧配置文件，正在删除..."
    $SUDO rm -f /etc/modules-load.d/matpool-mpu.conf
    echo "✅ 已删除 /etc/modules-load.d/matpool-mpu.conf"
fi

# 删除系统目录的旧模块文件（如果有）
if [ -f "/lib/modules/$(uname -r)/extra/mpu.ko" ]; then
    echo "发现系统目录中的旧模块文件..."
    $SUDO rm -f /lib/modules/$(uname -r)/extra/mpu.ko
    echo "✅ 已删除旧模块文件"
fi

echo ""
echo "步骤 2/7: 创建系统模块目录"
echo "--------------------"
$SUDO mkdir -p /lib/modules/$(uname -r)/extra/
echo "✅ 目录已准备：/lib/modules/$(uname -r)/extra/"

echo ""
echo "步骤 3/7: 复制模块到系统目录"
echo "--------------------"
$SUDO cp mpu.ko /lib/modules/$(uname -r)/extra/
echo "✅ 已复制 mpu.ko 到系统目录"

echo ""
echo "步骤 4/7: 更新模块依赖关系"
echo "--------------------"
$SUDO depmod -a
echo "✅ 模块依赖关系已更新"

echo ""
echo "步骤 5/7: 配置开机自动加载"
echo "--------------------"
echo "mpu" | $SUDO tee /etc/modules-load.d/mpu.conf > /dev/null
echo "✅ 已创建 /etc/modules-load.d/mpu.conf"

echo ""
echo "步骤 6/7: 加载模块"
echo "--------------------"
$SUDO modprobe mpu
echo "✅ 模块已加载"

echo ""
echo "步骤 7/7: 验证安装"
echo "--------------------"

# 检查模块是否加载
if lsmod | grep -q "^mpu "; then
    echo "✅ 模块加载成功"
    lsmod | grep "^mpu"
else
    echo "❌ 模块加载失败"
    echo "请查看内核日志：sudo dmesg | grep -i mpu | tail -20"
    exit 1
fi

# 检查模块路径
echo ""
echo "模块文件位置："
modinfo mpu | grep filename

# 检查是否在系统目录
if modinfo mpu | grep filename | grep -q "/lib/modules/"; then
    echo "✅ 模块在系统目录中"
    echo "   可以安全删除项目源码目录"
else
    echo "⚠️  警告：模块不在系统目录中"
fi

# 检查自动加载配置
echo ""
echo "开机自动加载配置："
cat /etc/modules-load.d/mpu.conf

echo ""
echo "========================================="
echo "✅ 安装完成！"
echo "========================================="
echo ""
echo "📝 后续操作："
echo ""
echo "1. 测试功能："
echo "   docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi"
echo ""
echo "2. 查看模块状态："
echo "   lsmod | grep mpu"
echo "   modinfo mpu"
echo ""
echo "3. 查看内核日志："
echo "   sudo dmesg | grep -i mpu | tail -10"
echo ""
echo "4. 卸载模块（如需要）："
echo "   sudo bash uninstall.sh"
echo ""
echo "5. 重启测试（可选但推荐）："
echo "   sudo reboot"
echo "   # 重启后检查：lsmod | grep mpu"
echo ""
