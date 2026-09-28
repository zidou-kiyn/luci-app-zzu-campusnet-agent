# SPDX-License-Identifier: MIT
#
# Build with the OpenWrt/ImmortalWrt SDK:
#   place this folder under package/ and run `make package/luci-app-zzu-campusnet-agent/compile`

include $(TOPDIR)/rules.mk

LUCI_TITLE:=ZZU CampusNet Agent - eportal status, login/logout & daily re-auth
# 留空依赖:本包纯脚本,运行时只需 luci-base(LuCI 系统必带);
# 若声明 +luci-base,SDK 会递归编译整个 luci-base 依赖链(需 base/packages feed 源码),得不偿失
LUCI_DEPENDS:=
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-zzu-campusnet-agent
PKG_VERSION:=1.1.0
PKG_RELEASE:=1
PKG_MAINTAINER:=luci-app-zzu-campusnet-agent
PKG_LICENSE:=MIT

# 标记为配置文件:升级/重装时保留用户已填的账号、密码等设置
define Package/luci-app-zzu-campusnet-agent/conffiles
/etc/config/zzucampusnetagent
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
