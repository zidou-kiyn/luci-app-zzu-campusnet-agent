# SPDX-License-Identifier: MIT
#
# Build with the OpenWrt/ImmortalWrt SDK:
#   place this folder under package/ and run `make package/luci-app-zzu-campusnet-agent/compile`

include $(TOPDIR)/rules.mk

LUCI_TITLE:=ZZU CampusNet Agent - eportal status, login/logout & daily re-auth
LUCI_DEPENDS:=
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-zzu-campusnet-agent
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_MAINTAINER:=luci-app-zzu-campusnet-agent
PKG_LICENSE:=MIT

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
