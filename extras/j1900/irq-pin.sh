#!/bin/sh
# /usr/sbin/irq-pin.sh：Redmi AX5400 (IPQ5018 双核) AP 中断固定分配，由 /etc/rc.local 开机执行
#   CPU0：有线网口 nss-dp-gmac + 2.4G（SoC 内置 ath11k，GIC 中断）
#   CPU1：5G（QCN9074，PCIe MSI 中断，设备 0000:01:00.0）
grep -E 'nss-dp-gmac|GIC-0 .* (ce[0-9]+|wbm2host|reo2|ppdu|rxdma|host2)' /proc/interrupts | cut -d: -f1 | while read i; do
	echo 1 > /proc/irq/$i/smp_affinity 2>/dev/null
done
grep 'PCI-MSI-0000:01:00.0' /proc/interrupts | cut -d: -f1 | while read i; do
	echo 2 > /proc/irq/$i/smp_affinity 2>/dev/null
done
