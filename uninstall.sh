#!/bin/bash
# MPU 模块完整卸载脚本

set -e  # 遇到错误立即退出

echo "========================================="
echo "MPU 模块卸载脚本"
echo "========================================="
echo ""

# 检查是否有 root 权限
if [ "$EUID" -ne 0 ]; then
    echo "⚠️  此脚本需要 root 权限"
    echo "将使用 sudo 运行命令..."
    SUDO="sudo"
else
    SUDO=""
fi

echo "步骤 1/5: 卸载内核模块"
echo "--------------------"

# 检查模块是否已加载
if lsmod | grep -q "^mpu "; then
    echo "检测到已加载的 mpu 模块，正在卸载..."
    $SUDO rmmod mpu
    echo "✅ 模块已卸载"
else
    echo "ℹ️  模块未加载，跳过"
fi

echo ""
echo "步骤 2/5: 删除自动加载配置文件"
echo "--------------------"

# 删除新配置文件
if [ -f "/etc/modules-load.d/mpu.conf" ]; then
    echo "删除 /etc/modules-load.d/mpu.conf"
    $SUDO rm -f /etc/modules-load.d/mpu.conf
    echo "✅ 已删除"
else
    echo "ℹ️  配置文件不存在，跳过"
fi

# 删除旧配置文件（make install 创建的）
if [ -f "/etc/modules-load.d/matpool-mpu.conf" ]; then
    echo "删除 /etc/modules-load.d/matpool-mpu.conf"
    $SUDO rm -f /etc/modules-load.d/matpool-mpu.conf
    echo "✅ 已删除"
else
    echo "ℹ️  旧配置文件不存在，跳过"
fi

echo ""
echo "步骤 3/5: 删除系统模块文件"
echo "--------------------"

if [ -f "/lib/modules/$(uname -r)/extra/mpu.ko" ]; then
    echo "删除 /lib/modules/$(uname -r)/extra/mpu.ko"
    $SUDO rm -f /lib/modules/$(uname -r)/extra/mpu.ko
    echo "✅ 已删除"
else
    echo "ℹ️  系统模块文件不存在，跳过"
fi

echo ""
echo "步骤 4/5: 更新模块依赖关系"
echo "--------------------"
$SUDO depmod -a
echo "✅ 模块依赖关系已更新"

echo ""
echo "步骤 5/5: 验证卸载"
echo "--------------------"

# 检查模块是否还在加载
if lsmod | grep -q "^mpu "; then
    echo "⚠️  警告：模块仍在加载中"
    lsmod | grep "^mpu"
else
    echo "✅ 模块未加载"
fi

# 检查是否能找到模块
if modprobe -n mpu 2>&1 | grep -q "not found\|找不到"; then
    echo "✅ 模块已从系统中移除"
else
    echo "⚠️  警告：系统仍能找到 mpu 模块"
    modinfo mpu 2>/dev/null || true
fi

echo ""
echo "========================================="
echo "✅ 卸载完成！"
echo "========================================="
echo ""
echo "📝 验证命令："
echo "   lsmod | grep mpu          # 应该没有输出"
echo "   modprobe -n mpu           # 应该报错找不到模块"
echo ""
echo "🔄 如需重新安装："
echo "   ./install_clean.sh"
echo ""

