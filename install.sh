#!/bin/sh
# ============================================================
#  luci-app-zzu-campusnet-agent 安装 / 更新脚本（在 ImmortalWrt 路由器上运行）
#  安装或更新：  sh install.sh
#  卸载：        sh install.sh uninstall
#  说明：重复运行即为“更新”，会覆盖程序文件但保留 /etc/config/zzucampusnetagent 里的账号等设置
# ============================================================
set -e

JS_DIR="/www/luci-static/resources/view/zzucampusnetagent"
RPCD="/usr/libexec/rpcd/luci.zzucampusnetagent"
BIN="/usr/sbin/zzucampusnetagent"
INITD="/etc/init.d/zzucampusnetagent"
MENU="/usr/share/luci/menu.d/luci-app-zzu-campusnet-agent.json"
ACL="/usr/share/rpcd/acl.d/luci-app-zzu-campusnet-agent.json"
CFG="/etc/config/zzucampusnetagent"

# 旧版本遗留文件（旧包名 luci-app-zzustatus / 旧内部名 zzustatus），升级时清理并迁移配置
OLD_MENU="/usr/share/luci/menu.d/luci-app-zzustatus.json"
OLD_ACL="/usr/share/rpcd/acl.d/luci-app-zzustatus.json"
OLD_JS_DIR="/www/luci-static/resources/view/zzustatus"
OLD_RPCD="/usr/libexec/rpcd/luci.zzustatus"
OLD_BIN="/usr/sbin/zzustatus"
OLD_INITD="/etc/init.d/zzustatus"
OLD_CFG="/etc/config/zzustatus"

if [ "$1" = "uninstall" ]; then
	echo "==> 卸载 luci-app-zzu-campusnet-agent ..."
	[ -x "$INITD" ] && { "$INITD" stop 2>/dev/null || true; "$INITD" disable 2>/dev/null || true; }
	rm -rf "$JS_DIR" "$OLD_JS_DIR"
	rm -f "$RPCD" "$BIN" "$INITD" "$MENU" "$ACL" "$CFG" "$OLD_MENU" "$OLD_ACL" "$OLD_RPCD" "$OLD_BIN" "$OLD_INITD" "$OLD_CFG"
	[ -f /etc/crontabs/root ] && sed -i -e '\|zzucampusnetagent-reauth|d' -e '\|zzucampusnetagent-watchdog|d' -e '\|zzustatus-reauth|d' /etc/crontabs/root 2>/dev/null || true
	/etc/init.d/cron restart 2>/dev/null || true
	rm -f /tmp/luci-indexcache* 2>/dev/null || true
	rm -rf /tmp/luci-modulecache 2>/dev/null || true
	/etc/init.d/rpcd restart 2>/dev/null || true
	echo "==> 已卸载。"
	exit 0
fi

echo "==> 安装/更新 luci-app-zzu-campusnet-agent ..."
mkdir -p "$JS_DIR" /usr/libexec/rpcd /usr/sbin /etc/init.d /usr/share/luci/menu.d /usr/share/rpcd/acl.d /etc/config
# 清理旧版本（zzustatus）遗留文件：程序、菜单、ACL、cron 任务
[ -x "$OLD_INITD" ] && { "$OLD_INITD" stop 2>/dev/null || true; "$OLD_INITD" disable 2>/dev/null || true; } || true
rm -f "$OLD_MENU" "$OLD_ACL" "$OLD_RPCD" "$OLD_BIN" "$OLD_INITD"
rm -rf "$OLD_JS_DIR"
[ -f /etc/crontabs/root ] && sed -i '\|zzustatus-reauth|d' /etc/crontabs/root 2>/dev/null || true

# 迁移旧配置 /etc/config/zzustatus → 新配置（保留账号、密码等已填设置）
if [ -f "$OLD_CFG" ] && [ ! -f "$CFG" ]; then
	sed 's/^config zzustatus/config zzucampusnetagent/' "$OLD_CFG" > "$CFG"
fi
rm -f "$OLD_CFG"

# ---------- 前端视图 ----------
cat > "$JS_DIR/status.js" <<'ZZU_EOF_JS'
'use strict';
'require view';
'require form';
'require rpc';
'require poll';
'require dom';
'require ui';
'require tools.widgets as widgets';

var callStatus = rpc.declare({ object: 'luci.zzucampusnetagent', method: 'status', expect: { } });
var callLogin  = rpc.declare({ object: 'luci.zzucampusnetagent', method: 'login',  params: [ 'line' ], expect: { } });
var callLogout = rpc.declare({ object: 'luci.zzucampusnetagent', method: 'logout', params: [ 'line' ], expect: { } });
var callReauth = rpc.declare({ object: 'luci.zzucampusnetagent', method: 'reauth', params: [ 'line' ], expect: { } });

// 颜色全部收敛为 --zzu-* 变量；暗色由 prefers-color-scheme 或 .zzu-dark 触发，.zzu-light 可强制亮色
var DARK_VARS = '--zzu-pt:#a3aeff;--zzu-ok:#2fc98c;--zzu-warn:#f5ad55;--zzu-err:#f07892;--zzu-et:#f497ab;--zzu-bg:#282838;--zzu-bg2:#21212f;--zzu-tx:#e8ebf3;--zzu-tx2:#bfc3d6;--zzu-mu:#9ca2ba;--zzu-bd:rgba(255,255,255,.08);--zzu-bd2:rgba(255,255,255,.15);--zzu-in:#2f2f43;--zzu-sk:rgba(255,255,255,.09);--zzu-sh:0 8px 24px rgba(0,0,0,.32);--zzu-sh2:0 16px 36px rgba(0,0,0,.45)';

var STYLE = `
.zzu-page{--zzu-pri:#5e72e4;--zzu-pd:#4a5bd0;--zzu-pt:#4a5bd0;--zzu-ok:#19b377;--zzu-warn:#f0a13c;--zzu-err:#ea5f7e;--zzu-et:#c43a5c;--zzu-c2:#1a9fc2;--zzu-c4:#8965e0;--zzu-bg:#fff;--zzu-bg2:#f6f8fc;--zzu-tx:#32325d;--zzu-tx2:#525f7f;--zzu-mu:#6b7894;--zzu-bd:rgba(50,50,93,.09);--zzu-bd2:#dce0e9;--zzu-in:#fff;--zzu-sk:rgba(50,50,93,.08);--zzu-sh:0 6px 20px rgba(50,50,93,.09);--zzu-sh2:0 14px 32px rgba(50,50,93,.18);box-sizing:border-box;width:100%;max-width:980px;margin:0 auto 24px;container-type:inline-size;color:var(--zzu-tx);font-family:-apple-system,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif}
@media(prefers-color-scheme:dark){.zzu-page:not(.zzu-light){${DARK_VARS}}}
.zzu-dark .zzu-page,.zzu-page.zzu-dark{${DARK_VARS}}
.zzu-i{width:16px;height:16px;flex:none;fill:none;stroke:currentColor;stroke-width:1.75;stroke-linecap:round;stroke-linejoin:round}
@keyframes zzuPulse{from{transform:scale(1);opacity:.8}to{transform:scale(1.5);opacity:0}}
@keyframes zzuSpin{to{transform:rotate(360deg)}}
@keyframes zzuTick{to{stroke-dashoffset:100}}
@keyframes zzuBar{to{transform:scaleX(0)}}
@keyframes zzuToast{from{opacity:0;transform:translateY(-8px)}}
/* 状态色：深一档保证白字 ≥4.5:1 */
.zzu-line{margin-bottom:22px;--zzu-c:#b02e58;--zzu-g:linear-gradient(135deg,#c93a5d,#b02e58)}
.zzu-line:last-child{margin-bottom:0}
.zzu-line.is-online{--zzu-c:#0b7470;--zzu-g:linear-gradient(135deg,#0d8058,#0b7470)}
.zzu-line.is-offline{--zzu-c:#a3421a;--zzu-g:linear-gradient(135deg,#b0560c,#a3421a)}
.zzu-line.is-nonet{--zzu-c:#8a4b08;--zzu-g:linear-gradient(135deg,#9a6206,#8a4b08)}
/* 横幅 */
.zzu-banner{position:relative;border-radius:16px;padding:22px 24px 58px;color:#fff;background:radial-gradient(circle at 100% 0,rgba(255,255,255,.16),transparent 55%),var(--zzu-g);box-shadow:0 14px 30px -12px var(--zzu-c)}
.zzu-banner-in{display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap}
.zzu-banner-l{display:flex;align-items:center;gap:14px;min-width:0;flex:1 1 300px}
.zzu-head{min-width:0}
.zzu-badge{position:relative;width:52px;height:52px;flex:none;display:grid;place-items:center;background:rgba(255,255,255,.18);border:1px solid rgba(255,255,255,.3);border-radius:14px}
.zzu-badge .zzu-i{width:26px;height:26px;stroke-width:2}
.zzu-badge.pulse::after{content:"";position:absolute;inset:-1px;border-radius:inherit;border:2px solid rgba(255,255,255,.6);animation:zzuPulse 2.4s cubic-bezier(.2,.6,.3,1) infinite}
.zzu-title-row{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.zzu-title{font-size:20px;font-weight:700;letter-spacing:.3px}
.zzu-pill{display:inline-flex;align-items:center;gap:6px;font-size:12px;font-weight:600;background:rgba(0,0,0,.16);border-radius:99px;padding:3px 10px;white-space:nowrap;font-variant-numeric:tabular-nums}
.zzu-sub{display:flex;flex-direction:column;align-items:flex-start;gap:6px;margin-top:6px;font-size:12.5px}
.zzu-reason{display:flex;gap:6px;font-size:13.5px;font-weight:600;line-height:1.45;background:rgba(0,0,0,.18);border-radius:10px;padding:6px 11px 6px 9px;word-break:break-all}
.zzu-reason .zzu-i{margin-top:2px}
.is-online .zzu-reason{display:none}
.zzu-time{font-variant-numeric:tabular-nums}
.zzu-ring{width:14px;height:14px;flex:none;transform:rotate(-90deg)}
.zzu-ring circle{fill:none;stroke:currentColor;stroke-width:2.5;opacity:.3}
.zzu-ring circle+circle{opacity:1;stroke-dasharray:100;animation:zzuTick 10s linear infinite}
/* 按钮：默认幽灵；非在线时"登录"为主；在线时"注销"为描边 */
.zzu-acts{display:flex;gap:8px}
.zzu-btn{display:inline-flex;align-items:center;justify-content:center;gap:6px;height:36px;padding:0 14px;cursor:pointer;border:1.5px solid transparent;border-radius:10px;background:rgba(255,255,255,.15);color:#fff;font-family:inherit;font-size:13px;font-weight:600;white-space:nowrap;transition:background .15s,transform .15s,box-shadow .15s}
.zzu-btn:hover{background:rgba(255,255,255,.26)}
.zzu-btn:active{transform:translateY(1px)}
.zzu-btn:focus-visible{outline:2px solid #fff;outline-offset:2px}
.zzu-line:not(.is-online) .zzu-btn.login{background:#fff;color:var(--zzu-c);font-weight:700;box-shadow:0 4px 12px rgba(0,0,0,.18)}
.zzu-line:not(.is-online) .zzu-btn.login:hover{transform:translateY(-1px);box-shadow:0 7px 16px rgba(0,0,0,.22)}
.is-online .zzu-btn.logout{background:none;border-color:rgba(255,255,255,.7)}
.is-online .zzu-btn.logout:hover{background:rgba(255,255,255,.14)}
.zzu-btn[disabled],.zzu-save[disabled]{opacity:.6;cursor:default;transform:none!important}
/* 覆盖主题自带 .spinning（padding-left:32px!important + 背景 gif） */
.zzu-btn.spinning,.zzu-save.spinning{cursor:progress;position:relative}
.zzu-btn.spinning{padding-left:14px!important}
.zzu-save.spinning{padding-left:22px!important}
:is(.zzu-btn,.zzu-save).spinning .zzu-i{display:none}
:is(.zzu-btn,.zzu-save).spinning::before{content:"";position:static;flex:none;box-sizing:border-box;margin:0;width:13px;height:13px;background:none;border:2px solid currentColor;border-right-color:transparent;border-radius:50%;animation:zzuSpin .7s linear infinite}
/* 统计卡 */
.zzu-stats{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px;margin:-36px 18px 0;position:relative;z-index:1}
.zzu-stat{display:flex;align-items:center;gap:12px;min-width:0;padding:14px 16px;background:var(--zzu-bg);border:1px solid var(--zzu-bd);border-radius:14px;box-shadow:var(--zzu-sh);transition:transform .18s,box-shadow .18s}
.is-online .zzu-stat:hover{transform:translateY(-2px);box-shadow:var(--zzu-sh2)}
.zzu-stat-ico{width:38px;height:38px;flex:none;display:grid;place-items:center;border-radius:11px;color:var(--zzu-pri);background:color-mix(in srgb,currentColor 13%,transparent)}
.zzu-stat:nth-child(2) .zzu-stat-ico{color:var(--zzu-c2)}
.zzu-stat:nth-child(3) .zzu-stat-ico{color:var(--zzu-warn)}
.zzu-stat:nth-child(4) .zzu-stat-ico{color:var(--zzu-c4)}
.zzu-stat-ico .zzu-i{width:19px;height:19px}
.zzu-stat-k{font-size:12px;color:var(--zzu-mu);white-space:nowrap}
.zzu-stat-v{margin-top:3px;font-size:14.5px;font-weight:700;font-variant-numeric:tabular-nums;word-break:break-all}
.zzu-line:not(.is-online):not(.is-nonet) .zzu-stat-ico{color:var(--zzu-mu);opacity:.6}
.zzu-line:not(.is-online):not(.is-nonet) .zzu-stat-v{width:62%;height:10px;margin-top:7px;border-radius:5px;background:var(--zzu-sk);color:transparent;overflow:hidden}
.zzu-copy{cursor:copy;text-decoration:underline dashed transparent;text-underline-offset:3px;transition:text-decoration-color .15s}
.zzu-copy:hover{text-decoration-color:var(--zzu-mu)}
.zzu-copy.copied::after{content:" 已复制";font-size:11px;color:var(--zzu-ok)}
/* 多线路：汇总条 + 紧凑卡 */
.zzu-sum{grid-column:1/-1;display:flex;flex-wrap:wrap;align-items:center;gap:8px 16px;padding:12px 18px;background:var(--zzu-bg);border:1px solid var(--zzu-bd);border-radius:14px;box-shadow:var(--zzu-sh);font-size:13px;color:var(--zzu-tx2)}
.zzu-sum b{font-size:14px;color:var(--zzu-tx)}
.zzu-chip{display:inline-flex;align-items:center;gap:6px;font-weight:600}
.zzu-chip::before{content:"";width:8px;height:8px;border-radius:50%;background:var(--zzu-err)}
.zzu-chip.is-online::before{background:var(--zzu-ok)}
.zzu-chip.is-offline::before{background:var(--zzu-warn)}
.zzu-chip.is-nonet::before{background:#d9480f}
.zzu-sum-t{margin-left:auto;display:inline-flex;align-items:center;gap:6px;color:var(--zzu-mu);font-variant-numeric:tabular-nums}
.zzu-sum-t .zzu-ring{color:var(--zzu-pri)}
.zzu-multi{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}
.zzu-multi .zzu-line{margin:0;display:flex;flex-direction:column;overflow:hidden;background:var(--zzu-bg);border:1px solid var(--zzu-bd);border-radius:16px;box-shadow:var(--zzu-sh)}
.zzu-multi .zzu-banner{flex:1;border-radius:0;padding:16px 18px;box-shadow:none}
.zzu-multi .zzu-banner-in{flex-direction:column;align-items:stretch;gap:14px}
.zzu-multi .zzu-banner-l{flex:none;gap:12px}
.zzu-multi .zzu-badge{width:42px;height:42px;border-radius:12px}
.zzu-multi .zzu-badge .zzu-i{width:22px;height:22px}
.zzu-multi .zzu-title{font-size:16.5px}
.zzu-multi .zzu-time{display:none}
.zzu-multi .zzu-acts{display:grid;grid-template-columns:repeat(3,1fr)}
.zzu-multi .zzu-btn{height:34px}
.zzu-multi .zzu-stats{margin:0;gap:0;grid-template-columns:1fr 1fr}
.zzu-multi .zzu-stat{border:0;border-radius:0;box-shadow:none!important;transform:none!important;padding:12px 18px}
.zzu-multi .zzu-stat:nth-child(odd){border-right:1px solid var(--zzu-bd)}
.zzu-multi .zzu-stat:nth-child(n+3){border-top:1px solid var(--zzu-bd)}
.zzu-multi .zzu-stat-ico{width:32px;height:32px;border-radius:9px}
/* 提示条 toast */
#zzu-msg{position:fixed;top:80px;right:24px;z-index:1050;width:min(380px,calc(100vw - 24px));display:grid;gap:10px;pointer-events:none}
.zzu-alert{position:relative;overflow:hidden;pointer-events:auto;display:flex;align-items:flex-start;gap:10px;padding:13px 12px 15px 14px;border-radius:12px;background:var(--zzu-bg);border:1px solid var(--zzu-bd);box-shadow:var(--zzu-sh2);font-size:13.5px;line-height:1.5;animation:zzuToast .28s cubic-bezier(.2,.8,.3,1)}
.zzu-alert-ico{width:22px;height:22px;flex:none;display:grid;place-items:center;border-radius:50%;color:#fff;background:var(--zzu-ok)}
.zzu-alert-ico .zzu-i{width:13px;height:13px;stroke-width:2.6}
.zzu-alert-txt{flex:1;font-weight:500;word-break:break-all}
.zzu-alert-x{display:grid;padding:3px;border-radius:6px;cursor:pointer;color:var(--zzu-mu)}
.zzu-alert-x:hover{color:var(--zzu-tx);background:var(--zzu-bg2)}
.zzu-alert-bar{position:absolute;left:0;bottom:0;width:100%;height:3px;background:var(--zzu-ok);transform-origin:left;animation:zzuBar 6s linear forwards}
.zzu-alert.err :is(.zzu-alert-ico,.zzu-alert-bar){background:var(--zzu-err)}
/* 设置卡 */
.zzu-settings{margin-top:22px;background:var(--zzu-bg);border:1px solid var(--zzu-bd);border-radius:16px;box-shadow:var(--zzu-sh)}
.zzu-set-hd{display:flex;align-items:center;gap:10px;padding:18px 24px;cursor:pointer;user-select:none;font-size:15px;font-weight:700}
.zzu-set-hd>.zzu-i{width:18px;height:18px;color:var(--zzu-pri)}
.zzu-set-toggle{margin-left:auto;display:inline-flex;align-items:center;gap:4px;font-size:12.5px;font-weight:600;color:var(--zzu-pt)}
.zzu-set-toggle .zzu-i{transition:transform .2s}
.zzu-collapsed .zzu-set-toggle .zzu-i{transform:rotate(180deg)}
.zzu-collapsed :is(.zzu-set-bd,.zzu-set-ft){display:none}
.zzu-set-bd{padding:0 24px 8px;border-top:1px solid var(--zzu-bd)}
.zzu-set-ft{display:flex;justify-content:flex-end;padding:14px 24px 20px;border-top:1px solid var(--zzu-bd)}
.zzu-save{display:inline-flex;align-items:center;gap:8px;height:38px;padding:0 22px;cursor:pointer;border:0;border-radius:10px;background:var(--zzu-pd);color:#fff;font-family:inherit;font-size:13.5px;font-weight:600;box-shadow:0 4px 12px rgba(94,114,228,.35);transition:transform .15s,box-shadow .15s}
.zzu-save:hover{transform:translateY(-1px);box-shadow:0 7px 16px rgba(94,114,228,.45)}
.zzu-save:focus-visible{outline:2px solid var(--zzu-pri);outline-offset:2px}
/* LuCI 表单覆盖（仅作用域内） */
.zzu-set-bd :is(.cbi-map,.cbi-section,.cbi-section-node){background:transparent!important;box-shadow:none!important;border:none!important;margin:0!important;border-radius:0!important}
.zzu-set-bd .cbi-map-descr{margin:16px 0 6px;padding:10px 14px;border-radius:10px;background:var(--zzu-bg2);color:var(--zzu-tx2);font-size:12.5px;line-height:1.6}
/* argon 给 .cbi-value 设了 line-height:2.4rem，会把标题压低、输入框下方多出空隙 */
.zzu-set-bd .cbi-value{display:grid;grid-template-columns:190px minmax(0,1fr);gap:6px 24px;padding:14px 0;border-bottom:1px solid var(--zzu-bd);line-height:1.5}
.zzu-set-bd .cbi-value:last-child{border-bottom:0}
.zzu-set-bd .cbi-value-title{width:auto;padding:9px 0 0;line-height:20px;text-align:left;font-size:13.5px;font-weight:600;color:var(--zzu-tx)}
.zzu-set-bd .cbi-value-field{width:auto}
.zzu-set-bd .cbi-value-description{margin-top:6px;font-size:12px;line-height:1.55;color:var(--zzu-mu)}
.zzu-set-bd :is(.cbi-input-text,.cbi-input-password,.cbi-input-select){width:100%;max-width:360px;height:38px;padding:0 12px;border:1px solid var(--zzu-bd2);border-radius:10px;background:var(--zzu-in);color:var(--zzu-tx);font-size:13.5px;font-variant-numeric:tabular-nums;vertical-align:top;transition:border-color .15s,box-shadow .15s}
.zzu-set-bd :is(.cbi-input-text,.cbi-input-password,.cbi-input-select):focus{outline:0;border-color:var(--zzu-pri);box-shadow:0 0 0 3px rgba(94,114,228,.22)}
.zzu-set-bd .control-group{display:flex;flex-wrap:nowrap;gap:6px;max-width:360px}
.zzu-set-bd .control-group>input{flex:1;min-width:0}
.zzu-set-bd .control-group>.cbi-button{height:38px}
.zzu-set-bd .td .control-group{max-width:none}
/* argon: .control-group:has(>input+.cbi-button) input{width:15.5rem}，优先级高，需 !important 才能让表格收窄 */
.zzu-set-bd .td .control-group>input{width:0!important;flex:1 1 0}
.zzu-set-bd .cbi-dropdown{min-height:38px;border:1px solid var(--zzu-bd2);border-radius:10px;background:var(--zzu-in);color:var(--zzu-tx)}
.zzu-set-bd .cbi-dropdown .ifacebadge{background:none;border:0;box-shadow:none;padding:0}
.zzu-set-bd .cbi-dropdown .ifacebadge img{width:16px;height:16px;vertical-align:middle}
.zzu-set-bd input[type=checkbox]{appearance:none!important;-webkit-appearance:none!important;position:relative!important;display:inline-block!important;opacity:1!important;width:38px!important;height:22px!important;margin:8px 0 0!important;padding:0!important;border:0!important;border-radius:99px!important;background:var(--zzu-bd2)!important;cursor:pointer;vertical-align:middle;transition:background .2s}
.zzu-set-bd input[type=checkbox]::before{content:"";position:absolute;top:3px;left:3px;width:16px;height:16px;border-radius:50%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.25);transition:transform .2s}
.zzu-set-bd input[type=checkbox]::after{content:none!important;display:none!important}
.zzu-set-bd input[type=checkbox]:checked{background:var(--zzu-pri)!important}
.zzu-set-bd input[type=checkbox]:checked::before{transform:translateX(16px)}
.zzu-set-bd input[type=checkbox]:focus-visible{outline:2px solid var(--zzu-pri);outline-offset:2px}
.zzu-set-bd input[type=checkbox]+label{display:none!important}
.zzu-set-bd .td input[type=checkbox]{margin:0!important}
.zzu-set-bd .cbi-section h3{margin:26px 0 4px;padding:0;font-size:15px;color:var(--zzu-tx)}
.zzu-set-bd .cbi-section-descr{margin-bottom:10px;padding:0;font-size:12px;line-height:1.6;color:var(--zzu-mu)}
.zzu-set-bd .cbi-section-table .tr{background:transparent}
.zzu-set-bd .cbi-section-table{width:100%;margin-top:6px;border:1px solid var(--zzu-bd);border-radius:12px;border-collapse:separate;border-spacing:0;overflow:hidden}
.zzu-set-bd :is(.th,.td){padding:10px;border-bottom:1px solid var(--zzu-bd)}
.zzu-set-bd .th{background:var(--zzu-bg2);font-size:12px;font-weight:600;color:var(--zzu-mu);white-space:nowrap}
.zzu-set-bd .tr:last-child .td{border-bottom:0}
.zzu-set-bd .td :is(.cbi-input-text,.cbi-input-password,.cbi-input-select){min-width:110px!important;max-width:none}
.zzu-set-bd .td:nth-child(2) .cbi-input-text{min-width:80px!important}
.zzu-set-bd .td:nth-child(2){width:12%}
.zzu-set-bd .td:nth-child(6) .cbi-input-select{min-width:150px!important}
.zzu-set-bd .cbi-section-actions{width:1%;white-space:nowrap}
.zzu-set-bd .cbi-section-create{padding-left:0;padding-right:0}
.zzu-set-bd .cbi-button{white-space:nowrap;height:32px;padding:0 14px;cursor:pointer;border:1px solid var(--zzu-bd2);border-radius:8px;background:var(--zzu-in);color:var(--zzu-tx2);font-size:12.5px;font-weight:600}
.zzu-set-bd .cbi-button-add{border-color:transparent;background:color-mix(in srgb,var(--zzu-pri) 13%,transparent);color:var(--zzu-pt)!important}
.zzu-set-bd .cbi-button-remove{border-color:color-mix(in srgb,var(--zzu-err) 45%,transparent);color:var(--zzu-et)}
.zzu-set-bd .cbi-button:hover{filter:brightness(.96)}
@container (max-width:760px){.zzu-stats{grid-template-columns:1fr 1fr;margin:-36px 12px 0}}
@container (max-width:720px){.zzu-multi{grid-template-columns:minmax(0,1fr)}}
@media(max-width:720px){.zzu-set-bd .cbi-section-table{display:block;overflow-x:auto;-webkit-overflow-scrolling:touch}}
@media(max-width:600px){.zzu-set-bd .cbi-value{grid-template-columns:minmax(0,1fr)}.zzu-set-bd .cbi-value-title{padding:0}.zzu-set-bd .cbi-value-field :is(.cbi-input-text,.cbi-input-password,.cbi-input-select){width:100%;min-width:0;max-width:none}.zzu-set-bd .control-group{max-width:none}}
@media(max-width:480px){.zzu-banner{padding:18px 16px 46px;border-radius:14px}.zzu-badge{width:46px;height:46px}.zzu-title{font-size:18px}.zzu-acts{width:100%;display:grid;grid-auto-flow:column;grid-auto-columns:1fr}.zzu-btn,.zzu-btn.spinning{padding:0 8px!important}.zzu-stats{gap:10px;margin:-30px 10px 0}.zzu-stat{padding:11px 12px;gap:8px}.zzu-stat-ico{width:28px;height:28px;border-radius:9px}.zzu-stat-ico .zzu-i{width:16px;height:16px}.zzu-stat-v{font-size:13px}.zzu-sum{padding:12px 14px}.zzu-sum-t{margin-left:0;flex-basis:100%}.zzu-multi .zzu-stat{padding:11px 14px}.zzu-set-hd,.zzu-set-bd,.zzu-set-ft{padding-left:16px;padding-right:16px}.zzu-set-ft .zzu-save{flex:1;justify-content:center}#zzu-msg{top:8px;left:8px;right:8px;width:auto}}
@media(prefers-reduced-motion:reduce){.zzu-badge.pulse::after,.zzu-ring circle,.zzu-alert{animation:none!important}.zzu-page *{transition:none!important}}
`;

// 24 网格线性 SVG，描边/尺寸由 .zzu-i 控制
var ICONS = {
    check:   '<path d="M20 6 9 17l-5-5"/>',
    x:       '<path d="M18 6 6 18M6 6l12 12"/>',
    wifiOff: '<path d="M2 2l20 20M8.5 16.5a5 5 0 0 1 7 0M2 8.8a15 15 0 0 1 4.2-2.6M10.7 5a15 15 0 0 1 11.3 3.8M16.9 11.3a10 10 0 0 1 2.2 1.7M5 13a10 10 0 0 1 5.2-2.8M12 20h.01"/>',
    alert:   '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0zM12 9v4M12 17h.01"/>',
    info:    '<circle cx="12" cy="12" r="9"/><path d="M12 8v4M12 16h.01"/>',
    user:    '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    tower:   '<path d="M4.9 16.1a10 10 0 0 1 0-14.2M7.8 13.2a6 6 0 0 1 0-8.4M16.2 4.8a6 6 0 0 1 0 8.4M19.1 1.9a10 10 0 0 1 0 14.2"/><circle cx="12" cy="9" r="2"/><path d="M8 22l4-11 4 11M9.5 18h5"/>',
    clock:   '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    globe:   '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
    refresh: '<path d="M21 12a9 9 0 0 1-15.5 6.2L3 16M3 12a9 9 0 0 1 15.5-6.2L21 8M21 3v5h-5M3 21v-5h5"/>',
    login:   '<path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4M10 17l5-5-5-5M15 12H3"/>',
    power:   '<path d="M12 2v10M18.4 6.6a9 9 0 1 1-12.8 0"/>',
    sliders: '<path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6"/>',
    chevUp:  '<path d="m18 15-6-6-6 6"/>'
};
var RING = '<svg class="zzu-ring" viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="8" pathLength="100"/><circle cx="10" cy="10" r="8" pathLength="100"/></svg>';

var META = {
    online:  { label: '在线',     icon: 'check', pulse: true },
    nonet:   { label: '外网不通', icon: 'wifiOff' },
    offline: { label: '离线',     icon: 'wifiOff' },
    error:   { label: '连接异常', icon: 'alert' }
};

var STATS = [
    { key: 'account',  label: '账号',     icon: 'user',  copy: true },
    { key: 'carrier',  label: '运营商',   icon: 'tower' },
    { key: 'duration', label: '在线时长', icon: 'clock' },
    { key: 'ip',       label: 'IP 地址',  icon: 'globe', copy: true }
];

var ISPS = [
    [ 'campus',  '校园网 (无后缀)' ],
    [ 'cmcc',    '中国移动 (@cmcc)' ],
    [ 'unicom',  '中国联通 (@unicom)' ],
    [ 'telecom', '中国电信 (@telecom)' ],
    [ 'zzuplan', '学科专网 (@zzuplan)' ]
];

function fmt(v) { return (v === undefined || v === null || v === '') ? '—' : String(v); }
function stKey(s) { return META[s] ? s : 'error'; }
function hms(tsv) { return (tsv ? new Date(tsv * 1000) : new Date()).toLocaleTimeString('zh-CN', { hour12: false }); }

// 静态 SVG 字符串 → 节点（template 解析保证 SVG 命名空间正确）
function html(s) { var t = document.createElement('template'); t.innerHTML = s; return t.content.firstChild; }
function ico(n) { return html('<svg class="zzu-i" viewBox="0 0 24 24" aria-hidden="true">' + ICONS[n] + '</svg>'); }
function ring() { return html(RING); }

// LuCI 后台常为 http（非安全上下文），clipboard API 不可用或被拒时退回 execCommand
function copyText(s) {
    if (navigator.clipboard && window.isSecureContext)
        return navigator.clipboard.writeText(s).catch(function() { return copyLegacy(s); });
    return copyLegacy(s);
}

function copyLegacy(s) {
    var t = document.createElement('textarea'), ok = false;
    t.value = s;
    t.setAttribute('readonly', '');
    t.style.cssText = 'position:fixed;top:0;left:0;opacity:0';
    document.body.appendChild(t);
    t.select();
    try { ok = document.execCommand('copy'); } catch (e) {} finally { document.body.removeChild(t); }
    return ok ? Promise.resolve() : Promise.reject(new Error('copy failed'));
}

// 探测宿主主题实际底色：argon 强制暗色 / 强制亮色时与系统 prefers-color-scheme 可能不一致
function hostIsDark(el) {
    for (var n = el.parentNode; n && n.nodeType === 1; n = n.parentNode) {
        var m = (window.getComputedStyle(n).backgroundColor || '').match(/[\d.]+/g);
        if (m && m.length >= 3 && (m.length < 4 || +m[3] > 0.5))
            return (0.299 * m[0] + 0.587 * m[1] + 0.114 * m[2]) < 128;
    }
    return null;
}

// 占位线路（无线路 / 后端失败）：只显示原因和刷新按钮，不提供登录/注销
function stub(msg) { return { status: 'error', msg: msg, stub: true }; }

function normLines(res) {
    if (res && Array.isArray(res.lines) && res.lines.length) return res.lines;
    return [ (res && res.lines && res.lines[0] && res.lines[0].stub) ? res.lines[0]
        : stub('尚未配置认证线路：请在下方「认证线路」中添加一条并保存') ];
}

function addIsp(o) {
    ISPS.forEach(function(i) { o.value(i[0], i[1]); });
    o.default = 'campus';
}

return view.extend({
    handleRefresh: function() { return this.refresh(); },

    handleLogin: function(line) {
        var self = this;
        return callLogin(line).then(function(r) {
            r = r || {};
            self.showMsg(r.result == 1, '[' + self.lineName(line) + '] ' + (r.result == 1 ? '登录成功：' : '登录未成功：') + fmt(r.msg));
            return self.refresh();
        }).catch(function() { self.showMsg(false, '登录请求异常'); });
    },

    // 认证在线但外网不通：后端先注销再登录
    handleReauth: function(line) {
        var self = this;
        return callReauth(line).then(function(r) {
            r = r || {};
            self.showMsg(r.result == 1, '[' + self.lineName(line) + '] ' + (r.result == 1 ? '重新认证成功：' : '重新认证未成功：') + fmt(r.msg));
            return self.refresh();
        }).catch(function() { self.showMsg(false, '重新认证请求异常'); });
    },

    handleLogout: function(line) {
        var self = this;
        return callLogout(line).then(function(r) {
            r = r || {};
            self.showMsg(r.result == 1, '[' + self.lineName(line) + '] ' + (r.result == 1 ? '注销成功：' : '注销未成功：') + fmt(r.msg));
            return self.refresh();
        }).catch(function() { self.showMsg(false, '注销请求异常'); });
    },

    lineName: function(id) {
        var l = (this.lines || []).filter(function(x) { return x.id === id; })[0];
        return l && l.name ? l.name : id;
    },

    // 悬浮 toast：可手动关闭 + 6 秒自动消失（底部进度条同步）
    showMsg: function(ok, text) {
        var box = document.getElementById('zzu-msg');
        if (!box) return;
        var closer = E('span', { 'class': 'zzu-alert-x', 'title': '关闭' }, [ ico('x') ]);
        var alert = E('div', { 'class': 'zzu-alert ' + (ok ? 'ok' : 'err'), 'role': 'status' }, [
            E('span', { 'class': 'zzu-alert-ico' }, [ ico(ok ? 'check' : 'x') ]),
            E('span', { 'class': 'zzu-alert-txt' }, [ text ]),
            closer,
            E('span', { 'class': 'zzu-alert-bar' })
        ]);
        var remove = function() { if (alert && alert.parentNode) alert.parentNode.removeChild(alert); };
        closer.addEventListener('click', remove);
        dom.content(box, alert);
        window.setTimeout(remove, 6000);
    },

    refresh: function() {
        var self = this;
        return callStatus().then(function(res) {
            self.update(res || {});
        }).catch(function(e) {
            self.update({ lines: [ stub('后端调用失败：' + (e && e.message ? e.message : e)) ] });
        });
    },

    update: function(res) {
        var root = document.getElementById('zzu-root');
        if (!root) return;
        root.className = normLines(res).length > 1 ? 'zzu-multi' : '';
        dom.content(root, this.renderAll(res));
    },

    renderAll: function(res) {
        var self = this;
        res = res || {};
        var lines = normLines(res), multi = lines.length > 1;
        this.lines = lines;
        var nodes = lines.map(function(l) { return self.renderLine(l, res.ts, multi); });
        if (multi) nodes.unshift(this.renderSum(lines, res.ts));
        return nodes;
    },

    // 多线路汇总条：线路数 / 各状态计数 / 最近更新 + 刷新倒计时环
    renderSum: function(lines, tsv) {
        var c = { online: 0, nonet: 0, offline: 0, error: 0, removed: 0 };
        lines.forEach(function(l) { c[stKey(l.status)]++; if (l.removed) c.removed++; });
        return E('div', { 'class': 'zzu-sum' }, [
            E('b', {}, [ lines.length + ' 条线路' ]),
            E('span', { 'class': 'zzu-chip is-online' },  [ c.online + ' 在线' ]),
            c.nonet ? E('span', { 'class': 'zzu-chip is-nonet' }, [ c.nonet + ' 外网不通' ]) : '',
            c.removed ? E('span', { 'class': 'zzu-chip is-nonet', 'title': '外网不通，已从多路聚合中摘除；连续 2 次检测正常后自动加回' }, [ c.removed + ' 已摘除' ]) : '',
            E('span', { 'class': 'zzu-chip is-offline' }, [ c.offline + ' 离线' ]),
            E('span', { 'class': 'zzu-chip is-error' },   [ c.error + ' 异常' ]),
            E('span', { 'class': 'zzu-sum-t', 'title': '每 10 秒自动刷新' }, [ ring(), '最近更新 ' + hms(tsv) ])
        ]);
    },

    // 单条线路：横幅 + 统计卡（多线路时由 .zzu-multi 变为紧凑卡片）
    // 注意：动态文本一律放在数组里传给 E()，避免被当作 innerHTML 解析
    renderLine: function(res, tsv, multi) {
        var self = this;
        res = res || {};
        // nonet 仍有认证信息（账号/时长等），统计卡照常显示
        var st = stKey(res.status), m = META[st], on = st === 'online' || st === 'nonet';
        var id = res.id || '';
        var title = multi ? (fmt(res.name) + ' · ' + m.label) : m.label;

        var pill = multi
            ? E('span', { 'class': 'zzu-pill' }, [ (res.iface ? ('接口 ' + res.iface + (res.bind ? ' · ' + res.bind : '')) : '默认路由') + (res.removed ? ' · 已从聚合摘除' : '') ])
            : E('span', { 'class': 'zzu-pill', 'title': '每 10 秒自动刷新' }, [ ring(), '自动刷新' ]);

        var btn = function(role, icon, label, handler) {
            return E('button', { 'class': 'zzu-btn ' + role, 'click': ui.createHandlerFn(self, handler, id) }, [ ico(icon), label ]);
        };

        var banner = E('div', { 'class': 'zzu-banner' }, [
            E('div', { 'class': 'zzu-banner-in' }, [
                E('div', { 'class': 'zzu-banner-l' }, [
                    E('div', { 'class': 'zzu-badge' + (m.pulse ? ' pulse' : '') }, [ ico(m.icon) ]),
                    E('div', { 'class': 'zzu-head' }, [
                        E('div', { 'class': 'zzu-title-row' }, [
                            E('span', { 'class': 'zzu-title' }, [ title ]),
                            pill
                        ]),
                        E('div', { 'class': 'zzu-sub' }, [
                            E('span', { 'class': 'zzu-reason' }, [ ico('info'), fmt(res.msg) ]),
                            E('span', { 'class': 'zzu-time' }, [ '最近更新 ' + hms(tsv) ])
                        ])
                    ])
                ]),
                E('div', { 'class': 'zzu-acts' }, res.stub ? [
                    btn('refresh', 'refresh', '刷新', 'handleRefresh')
                ] : [
                    btn('refresh', 'refresh', '刷新', 'handleRefresh'),
                    st === 'nonet'
                        ? btn('login', 'refresh', '重新认证', 'handleReauth')
                        : btn('login', 'login',   '登录', 'handleLogin'),
                    btn('logout',  'power',   '注销', 'handleLogout')
                ])
            ])
        ]);

        var stats = E('div', { 'class': 'zzu-stats' }, STATS.map(function(s) {
            var val = on ? fmt(res[s.key]) : '—';
            var cp = on && s.copy && val !== '—';
            var v = cp
                ? E('div', { 'class': 'zzu-stat-v zzu-copy', 'title': '点击复制', 'click': function(ev) {
                        var el = ev.currentTarget;
                        copyText(val).then(function() {
                            el.classList.add('copied');
                            window.setTimeout(function() { el.classList.remove('copied'); }, 1500);
                        }).catch(function() {});
                    } }, [ val ])
                : E('div', { 'class': 'zzu-stat-v' }, [ val ]);
            return E('div', { 'class': 'zzu-stat' }, [
                E('div', { 'class': 'zzu-stat-ico' }, [ ico(s.icon) ]),
                E('div', { 'class': 'zzu-head' }, [ E('div', { 'class': 'zzu-stat-k' }, [ s.label ]), v ])
            ]);
        }));

        return E('div', { 'class': 'zzu-line is-' + st }, [ banner, stats ]);
    },

    load: function() {
        return callStatus().then(function(r) { return r || {}; }).catch(function() {
            return { lines: [ stub('后端调用失败') ] };
        });
    },

    // 保存按钮内置在设置卡片右下角，隐藏默认页脚
    addFooter: function() { return E([]); },

    render: function(data) {
        var self = this;

        var m = new form.Map('zzucampusnetagent', null,
            '修改后请点击右下角"保存并应用"。手动"登录/注销"使用的是已保存的配置。');
        var s = m.section(form.NamedSection, 'config', 'zzucampusnetagent');
        var o;

        o = s.option(form.Value, 'baseurl', '服务器地址 (Base URL)', '认证服务器地址，默认 172.16.4.14，无需带 http:// 与端口');
        o.placeholder = '172.16.4.14';
        o.default = '172.16.4.14';

        o = s.option(form.Flag, 'auto_relogin', '每天定时重新授权',
            '到点对所有线路执行：若在线则先注销，间隔 1 秒后重新登录，保证授权不掉线');
        o.default = '0';
        o.rmempty = false;

        o = s.option(form.Value, 'relogin_time', '定时时间', '24 小时制 HH:MM，默认 06:00（凌晨 6 点）');
        o.placeholder = '06:00';
        o.default = '06:00';
        o.depends('auto_relogin', '1');

        o = s.option(form.Flag, 'watchdog', '掉线自动重登',
            '定期检查所有线路：未登录时自动登录；开启外网检测时，认证在线但外网不通也会自动注销后重新登录');
        o.default = '0';
        o.rmempty = false;

        o = s.option(form.Value, 'watchdog_interval', '检查间隔（分钟）', '1–59，默认 5');
        o.datatype = 'range(1,59)';
        o.placeholder = '5';
        o.default = '5';
        o.depends('watchdog', '1');

        o = s.option(form.Flag, 'probe', '外网连通检测',
            '认证服务器只记录登录状态，运营商侧会话失效后仍会显示在线。开启后对在线的线路再以该线路 IP 访问检测地址，不通则显示“外网不通”（需要 curl）');
        o.default = '1';
        o.rmempty = false;

        o = s.option(form.Flag, 'failover', '故障线路自动摘除',
            '配合多线聚合（extras/99-multipath）：掉线检测发现线路重新认证后仍不通时，把它从聚合路由中暂时去掉，避免新连接分到坏线上打不开；连续 2 次检测正常后自动加回。同组线路全部故障时保留全部。需开启掉线自动重登与外网检测');
        o.default = '1';
        o.rmempty = false;
        o.depends({ watchdog: '1', probe: '1' });

        o = s.option(form.DynamicList, 'probe_url', '检测地址',
            '须返回 HTTP 204（任一通即算通）。留空使用默认：connect.rom.miui.com / connectivitycheck.platform.hicloud.com 的 /generate_204');
        o.placeholder = 'http://connect.rom.miui.com/generate_204';
        o.depends('probe', '1');

        // 认证线路：每行一条，以所选出口接口的 IP 向认证服务器登录（排在前面的先显示）
        var ls = m.section(form.TableSection, 'line', '认证线路',
            '每行一条线路。只有一条时出口接口留空即可（走系统默认路由）；多条时各自绑定一个已获取到校园网 IP 的接口（如 macvlan 虚拟 WAN），即可在不同出口同时登录不同运营商。每条线路的账号、密码各自填写（可以相同）。');
        ls.anonymous = true;
        ls.addremove = true;
        ls.addbtntitle = '添加线路';

        o = ls.option(form.Flag, 'enabled', '启用');
        o.default = '1';
        o.rmempty = false;

        o = ls.option(form.Value, 'name', '名称');
        o.placeholder = '如：电信1';

        o = ls.option(form.Value, 'account', '账号', '学号，不含 @后缀');
        o.placeholder = '学号';
        o.rmempty = false;

        o = ls.option(form.Value, 'password', '密码', '明文，自动编码');
        o.password = true;
        o.placeholder = '密码';
        o.rmempty = false;

        o = ls.option(widgets.NetworkSelect, 'iface', '出口接口', '留空 = 默认路由');
        o.nocreate = true;
        o.optional = true;
        o.rmempty = true;

        o = ls.option(form.ListValue, 'isp', '运营商');
        addIsp(o);

        return m.render().then(function(mapEl) {
            poll.add(function() { return self.refresh(); }, 10);

            var toggleTxt = E('span', {}, [ '收起' ]);
            var settings = E('div', { 'class': 'zzu-settings' }, [
                E('div', {
                    'class': 'zzu-set-hd',
                    'click': function() {
                        var collapsed = this.parentNode.classList.toggle('zzu-collapsed');
                        toggleTxt.textContent = collapsed ? '展开' : '收起';
                    }
                }, [
                    ico('sliders'),
                    E('span', {}, [ '账号与认证设置' ]),
                    E('span', { 'class': 'zzu-set-toggle' }, [ toggleTxt, ico('chevUp') ])
                ]),
                E('div', { 'class': 'zzu-set-bd' }, mapEl),
                E('div', { 'class': 'zzu-set-ft' }, [
                    E('button', {
                        'class': 'zzu-save',
                        'click': ui.createHandlerFn(self, 'handleSaveApply', '0')
                    }, [ '保存并应用' ])
                ])
            ]);

            var page = E('div', { 'class': 'zzu-page' }, [
                E('style', { 'type': 'text/css' }, STYLE),
                E('div', { 'id': 'zzu-msg' }),
                E('div', { 'id': 'zzu-root', 'class': normLines(data).length > 1 ? 'zzu-multi' : '' }, self.renderAll(data)),
                settings
            ]);

            // 挂载后按宿主主题实际底色锁定亮/暗，探测不到则交给 prefers-color-scheme
            var tries = 0;
            (function detect() {
                if (!page.isConnected) { if (++tries < 20) window.setTimeout(detect, 50); return; }
                var d = hostIsDark(page);
                if (d !== null) page.classList.add(d ? 'zzu-dark' : 'zzu-light');
            })();

            return page;
        });
    }
});
ZZU_EOF_JS

# ---------- 核心 CLI ----------
cat > "$BIN" <<'ZZU_EOF_BIN'
#!/bin/sh
# zzucampusnetagent - 郑大校园网 eportal 命令行核心（支持多线路）
#
# 用法:
#   zzucampusnetagent status              查询全部线路状态（JSON: {ts, lines:[...]}）
#   zzucampusnetagent query  [线路]       查询单条线路（默认第一条）
#   zzucampusnetagent login  [线路]       登录单条线路（默认第一条）
#   zzucampusnetagent logout [线路]       注销单条线路（默认第一条）
#   zzucampusnetagent reauth [线路]       注销→隔1s→登录；不带参数则对全部线路执行
#   zzucampusnetagent relogin [线路]      同 reauth（单条线路），输出登录结果 JSON（供页面调用）
#   zzucampusnetagent watchdog            检查全部线路：离线的自动登录；认证在线但外网不通的注销后重登；
#                                         仍不通的线路从多路聚合中摘除，恢复后自动加回
#   zzucampusnetagent migrate             把旧版配置迁移为新版（见 migrate()）
#
# 线路: UCI 中类型为 line 的段，段名即线路 id（旧版主线路迁移后为 "main"），
# 每条线路自带 account/password。config 段只存全局设置：服务器地址、定时重授权、掉线检测。
# 每条线路可绑定一个 netifd 逻辑接口（iface），请求会以该接口的 IP 为源地址发出，
# 从而让同一账号在不同出口上分别以不同运营商认证；iface 留空则走系统默认路由。
#
# 外网检测（config.probe，默认开启）：认证服务器只记录“登录过”，运营商侧会话失效后
# 仍会返回在线。因此对“在线”的线路再以该线路 IP 请求 probe_url（期望 HTTP 204），
# 不通则判定为 nonet（认证在线但外网不通），watchdog 会对其注销后重新登录。
#
# 故障摘除（config.failover，默认开启，需外网检测）：watchdog 处理完毕后线路仍不通，
# 写标记 $DOWN_DIR/<设备名> 并调用 99-multipath 重建组路由（该脚本跳过有标记的设备）。
# 被摘除的线路仍以自己的源 IP 走自己的路由表，照常检测；连续 FO_RECOVER 次正常后恢复。
. /usr/share/libubox/jshn.sh
. /lib/functions/network.sh

CFG="zzucampusnetagent"
TAG="zzucampusnetagent"
LOCK="/var/lock/zzucampusnetagent.lock"
MLOCK="/var/lock/zzucampusnetagent.migrate.lock"

cfg() { uci -q get "${CFG}.config.$1" 2>/dev/null; }
base() { local b; b=$(cfg baseurl); echo "${b:-172.16.4.14}"; }

# 线路 id 合法性（防注入）：只允许字母数字下划线
valid_id() { case "$1" in ""|*[!A-Za-z0-9_]*) return 1 ;; esac; return 0; }

# 读取线路属性（同名 line 段）
lget() { uci -q get "${CFG}.$1.$2" 2>/dev/null; }

line_exists() {
	valid_id "$1" || return 1
	[ "$(uci -q get "${CFG}.$1" 2>/dev/null)" = "line" ]
}

# 旧版配置：config 段里还有主线路设置（name/iface/isp）或共用账号密码（account/password）
has_legacy() { uci -q show "${CFG}.config" 2>/dev/null | grep -q "^${CFG}\.config\.\(name\|iface\|isp\|account\|password\)="; }

# 旧版 → 新版：
#   1. config 段的主线路设置搬到 line 段 'main'（排在最前）
#   2. 共用账号/密码填进没有自己账号/密码的线路（已有的不覆盖）
#   3. 删掉 config 段里的这些旧选项
migrate() {
	has_legacy || return 0
	(
		command -v flock >/dev/null 2>&1 && flock -x 8 2>/dev/null
		has_legacy || exit 0
		# 有主线路旧选项，或一条线路都没有（共用账号需要有处安放）→ 建 line 段 main
		if { uci -q show "${CFG}.config" | grep -q "^${CFG}\.config\.\(name\|iface\|isp\)=" ||
		     ! uci -q show "$CFG" | grep -q "=line\$"; } &&
		   [ "$(uci -q get "${CFG}.main")" != "line" ]; then
			uci -q delete "${CFG}.main"
			uci set "${CFG}.main=line"
			uci set "${CFG}.main.enabled=1"
			for o in name iface isp; do
				v=$(cfg "$o"); [ -n "$v" ] && uci set "${CFG}.main.$o=$v"
			done
			uci reorder "${CFG}.main=1"
		fi
		for o in account password; do
			v=$(cfg "$o"); [ -n "$v" ] || continue
			for id in $(uci -q show "$CFG" | sed -n "s/^${CFG}\.\([A-Za-z0-9_]*\)=line\$/\1/p"); do
				[ -n "$(lget "$id" "$o")" ] || uci set "${CFG}.${id}.${o}=$v"
			done
		done
		for o in name iface isp account password; do uci -q delete "${CFG}.config.$o"; done
		uci commit "$CFG"
		logger -t "$TAG" "migrated legacy config (main line / shared account) into line sections"
	) 8>"$MLOCK"
}

# 列出全部已启用线路（按 UCI 中的顺序）
line_ids() {
	local id
	for id in $(uci -q show "$CFG" 2>/dev/null | sed -n "s/^${CFG}\.\([A-Za-z0-9_]*\)=line\$/\1/p"); do
		[ "$(uci -q get "${CFG}.${id}.enabled" 2>/dev/null)" = "0" ] && continue
		echo "$id"
	done
}

line_name() {
	local n; n=$(lget "$1" name)
	[ -n "$n" ] && { echo "$n"; return; }
	[ "$1" = "main" ] && echo "主线路" || echo "$1"
}

isp_suffix() {
	case "$1" in
		cmcc)    echo "@cmcc" ;;
		unicom)  echo "@unicom" ;;
		telecom) echo "@telecom" ;;
		zzuplan) echo "@zzuplan" ;;
		campus|"") echo "" ;;
		@*)      echo "$1" ;;
		*)       echo "@$1" ;;
	esac
}

urlencode() {
	S="$1" awk 'BEGIN{
		s=ENVIRON["S"]
		for(i=0;i<256;i++)O[sprintf("%c",i)]=i
		h="0123456789ABCDEF"; n=length(s); o=""
		for(i=1;i<=n;i++){c=substr(s,i,1)
			if(c ~ /[A-Za-z0-9._~-]/){o=o c}
			else{v=O[c];o=o "%" substr(h,int(v/16)+1,1) substr(h,(v%16)+1,1)}
		}
		printf "%s",o
	}'
}

b64() {
	if command -v openssl >/dev/null 2>&1; then
		printf '%s' "$1" | openssl enc -base64 -A 2>/dev/null
	elif printf '' | base64 >/dev/null 2>&1; then
		printf '%s' "$1" | base64 2>/dev/null | tr -d '\n'
	else
		S="$1" awk 'BEGIN{
			s=ENVIRON["S"]
			for(i=0;i<256;i++)O[sprintf("%c",i)]=i
			b="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
			n=length(s); o=""
			for(i=1;i<=n;i+=3){
				c1=O[substr(s,i,1)]
				c2=(i+1<=n)?O[substr(s,i+1,1)]:0
				c3=(i+2<=n)?O[substr(s,i+2,1)]:0
				o=o substr(b,int(c1/4)+1,1)
				o=o substr(b,(int(c1%4)*16+int(c2/16))+1,1)
				o=o ((i+1<=n)?substr(b,(int(c2%16)*4+int(c3/64))+1,1):"=")
				o=o ((i+2<=n)?substr(b,(c3%64)+1,1):"=")
			}
			printf "%s",o
		}'
	fi
}

# 解析线路的出口源 IP，结果放在全局 BIND；ERR 为失败原因
# 未绑定接口 → BIND 为空（走系统默认路由，兼容单线路旧用法）
resolve_bind() {
	local iface
	BIND=""; ERR=""
	iface=$(lget "$1" iface)
	[ -z "$iface" ] && return 0
	if ! command -v curl >/dev/null 2>&1; then
		ERR="多线路绑定接口需要 curl（opkg/apk 安装 curl）"; return 1
	fi
	network_flush_cache
	network_get_ipaddr BIND "$iface"
	[ -n "$BIND" ] && return 0
	ERR="接口 ${iface} 未获取到 IPv4 地址（检查该接口是否已连接）"
	return 1
}

# fetch URL [源IP]
fetch() {
	local ref ua
	ref="http://$(base)/"
	ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
	if command -v curl >/dev/null 2>&1; then
		if [ -n "$2" ]; then
			curl -s --max-time 8 --interface "$2" -A "$ua" -e "$ref" "$1" 2>/dev/null
		else
			curl -s --max-time 8 -A "$ua" -e "$ref" "$1" 2>/dev/null
		fi
	elif command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -q -T 8 -U "$ua" -O - "$1" 2>/dev/null
	else
		wget -q -O - "$1" 2>/dev/null
	fi
}

strip_jsonp() { echo "$1" | sed -e 's/^[^(]*(//' -e 's/)[^)]*$//'; }

# ── 外网连通检测 ──
PROBE_URLS_DEFAULT="http://connect.rom.miui.com/generate_204 http://connectivitycheck.platform.hicloud.com/generate_204"

probe_on() { [ "$(cfg probe)" != "0" ]; }
probe_urls() { local u; u=$(cfg probe_url); echo "${u:-$PROBE_URLS_DEFAULT}"; }

# probe_net [源IP]：依次请求 probe_url，任一返回 HTTP 204 即为通
# 返回 0 通 / 1 不通 / 2 无法判断（无 curl、DNS 解析失败——不据此重登，避免误判）
# 只认 204：未认证时校园网会把 HTTP 劫持到认证页（200/302），不能算通
probe_net() {
	local u code rc tried=0
	command -v curl >/dev/null 2>&1 || return 2
	for u in $(probe_urls); do
		code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 \
			${1:+--interface "$1"} "$u" 2>/dev/null)
		rc=$?
		[ "$code" = "204" ] && return 0
		[ "$rc" = "6" ] && continue
		tried=1
	done
	[ "$tried" = "1" ] && return 1
	return 2
}

# 隔 3 秒两轮都不通才算不通（过滤瞬时抖动），供 watchdog 判定
net_down() {
	probe_net "$1"; [ $? -eq 1 ] || return 1
	sleep 3
	probe_net "$1"; [ $? -eq 1 ]
}

# ── 故障线路自动摘除（配合 extras/99-multipath）──
DOWN_DIR="/var/run/zzucampusnetagent/down"
MP_HOOK="/etc/hotplug.d/iface/99-multipath"
FO_RECOVER=2

failover_on() { [ "$(cfg failover)" != "0" ] && probe_on; }

# 线路绑定接口对应的三层设备名（接口已下线时退回接口名）；未绑定接口则为空
fo_dev() {
	local iface d=""
	iface=$(lget "$1" iface); [ -n "$iface" ] || return 0
	network_get_device d "$iface" 2>/dev/null
	d="${d:-$iface}"
	case "$d" in *[!A-Za-z0-9_.-]*) return 0 ;; esac
	echo "$d"
}

fo_removed() { local d; d=$(fo_dev "$1"); [ -n "$d" ] && [ -f "$DOWN_DIR/$d" ]; }

# 触发多路热插拔脚本重建该设备所在组的路由（未安装则只留标记）
mp_rebuild() {
	[ -f "$MP_HOOK" ] && ACTION=ifup INTERFACE="$1" DEVICE="$1" sh "$MP_HOOK" >/dev/null 2>&1
	return 0
}

# 线路外网健康：0 通 / 1 不通（隔 3 秒两轮都不通）/ 2 无法判断（含接口无 IP：多路脚本本就不会收录）
line_health() {
	local r
	resolve_bind "$1" || return 2
	probe_net "$BIND"; r=$?
	[ $r -eq 1 ] || return $r
	sleep 3
	probe_net "$BIND"
}

# 摘除（已摘除则清零恢复计数）
fo_mark() {
	local d; d=$(fo_dev "$1"); [ -n "$d" ] || return 0
	mkdir -p "$DOWN_DIR"
	if [ -f "$DOWN_DIR/$d" ]; then echo "$1 0" > "$DOWN_DIR/$d"; return 0; fi
	echo "$1 0" > "$DOWN_DIR/$d"
	logger -t "$TAG" "failover: [$1] $d removed from multipath (internet unreachable)"
	mp_rebuild "$d"
}

# 正常一次：已摘除的线路连续 FO_RECOVER 次正常才加回（防抖动反复切换）
fo_ok() {
	local d n
	d=$(fo_dev "$1"); [ -n "$d" ] && [ -f "$DOWN_DIR/$d" ] || return 0
	n=$(awk '{print $2+0}' "$DOWN_DIR/$d" 2>/dev/null); n=$((${n:-0} + 1))
	if [ "$n" -lt "$FO_RECOVER" ]; then echo "$1 $n" > "$DOWN_DIR/$d"; return 0; fi
	rm -f "$DOWN_DIR/$d"
	logger -t "$TAG" "failover: [$1] $d restored to multipath"
	mp_rebuild "$d"
}

# 清理失效标记：功能已关闭、线路已删除/禁用、线路换了接口
fo_gc() {
	local f id d
	[ -d "$DOWN_DIR" ] || return 0
	for f in "$DOWN_DIR"/*; do
		[ -f "$f" ] || continue
		d="${f##*/}"; id=""
		read -r id _ < "$f"
		if failover_on && line_exists "$id" && [ "$(lget "$id" enabled)" != "0" ] &&
		   [ "$(fo_dev "$id")" = "$d" ]; then
			continue
		fi
		rm -f "$f"
		logger -t "$TAG" "failover: stale marker for $d cleared"
		mp_rebuild "$d"
	done
}

# 向当前 json 对象写入线路查询结果字段
add_query_fields() {
	local id="$1" raw json result msg
	json_add_string id    "$id"
	json_add_string name  "$(line_name "$id")"
	json_add_string iface "$(lget "$id" iface)"
	json_add_string isp   "$(lget "$id" isp)"
	fo_removed "$id" && json_add_boolean removed 1
	if ! resolve_bind "$id"; then
		json_add_string status "error"
		json_add_string msg "$ERR"
		return
	fi
	json_add_string bind "$BIND"
	raw=$(fetch "http://$(base):801/eportal/portal/custom" "$BIND")
	if [ -z "$raw" ]; then
		json_add_string status "error"
		json_add_string msg "无法连接认证服务器（确认路由器已接入校园网）"
		return
	fi
	json=$(strip_jsonp "$raw")
	result=$(jsonfilter -s "$json" -e '@.result' 2>/dev/null)
	msg=$(jsonfilter -s "$json" -e '@.msg' 2>/dev/null)
	if [ "$result" = "1" ]; then
		local net=""
		if probe_on; then
			probe_net "$BIND"
			case $? in 0) net="ok" ;; 1) net="down" ;; *) net="unknown" ;; esac
			json_add_string net "$net"
		fi
		if [ "$net" = "down" ]; then
			json_add_string status "nonet"
			json_add_string msg "认证服务器显示在线，但外网不通（运营商侧会话可能已失效，可点「重新认证」）"
		else
			json_add_string status "online"
			json_add_string msg "${msg:-在线}"
		fi
		json_add_string account  "$(jsonfilter -s "$json" -e '@.data.param_account'  2>/dev/null)"
		json_add_string carrier  "$(jsonfilter -s "$json" -e '@.data.param_exit'     2>/dev/null)"
		json_add_string duration "$(jsonfilter -s "$json" -e '@.data.param_duration' 2>/dev/null)"
		json_add_string ip       "$(jsonfilter -s "$json" -e '@.data.param_ip'       2>/dev/null)"
	elif [ "$result" = "0" ]; then
		json_add_string status "offline"
		json_add_string msg "${msg:-当前无在线信息（可能未登录）}"
	else
		json_add_string status "error"
		json_add_string msg "${msg:-接口返回异常}"
	fi
}

# 纯文本状态：online / offline / error
query_state() {
	local raw json
	resolve_bind "$1" || { echo "error"; return; }
	raw=$(fetch "http://$(base):801/eportal/portal/custom" "$BIND")
	[ -z "$raw" ] && { echo "error"; return; }
	json=$(strip_jsonp "$raw")
	case "$(jsonfilter -s "$json" -e '@.result' 2>/dev/null)" in
		1) echo "online" ;; 0) echo "offline" ;; *) echo "error" ;;
	esac
}

# 含外网检测的状态：online / nonet / offline / error（用于日志）
line_state() {
	local st; st=$(query_state "$1")
	if [ "$st" = "online" ] && probe_on && resolve_bind "$1"; then
		probe_net "$BIND"; [ $? -eq 1 ] && st="nonet"
	fi
	echo "$st"
}

bad_line() {
	json_init
	json_add_int ts "$(date +%s)"
	json_add_int result 0
	json_add_string status "error"
	json_add_string msg "线路不存在：$1"
	json_dump
}

cmd_query() {
	line_exists "$1" || { bad_line "$1"; return; }
	json_init
	json_add_int ts "$(date +%s)"
	add_query_fields "$1"
	json_dump
}

# 各线路并行查询（每条含认证查询 + 外网检测，串行时多条线路异常会叠加超时）
cmd_status() {
	local id tmp n=0 sep="" out
	tmp=$(mktemp -d /tmp/zzucna.XXXXXX) || tmp="/tmp/zzucna.$$"
	mkdir -p "$tmp"
	for id in $(line_ids); do
		n=$((n + 1))
		echo "$id" > "$tmp/$n.id"
		( json_init; add_query_fields "$id"; json_dump > "$tmp/$n.json" ) &
	done
	wait
	out="{ \"ts\": $(date +%s), \"lines\": [ "
	id=1
	while [ "$id" -le "$n" ]; do
		if [ -s "$tmp/$id.json" ]; then
			out="$out$sep$(cat "$tmp/$id.json")"; sep=", "
		fi
		id=$((id + 1))
	done
	rm -rf "$tmp"
	echo "$out ] }"
}

cmd_login() {
	local id="$1" account password suffix acct pwb64 url raw json result msg
	line_exists "$id" || { bad_line "$id"; return; }
	account=$(lget "$id" account)
	password=$(lget "$id" password)
	suffix=$(isp_suffix "$(lget "$id" isp)")
	json_init
	json_add_int ts "$(date +%s)"
	json_add_string id "$id"
	if [ -z "$account" ] || [ -z "$password" ]; then
		json_add_int result 0
		json_add_string msg "请先在下方「认证线路」中填写该线路的账号和密码并保存"
		json_dump; return
	fi
	if ! resolve_bind "$id"; then
		json_add_int result 0
		json_add_string msg "$ERR"
		json_dump; return
	fi
	acct=$(urlencode ",0,${account}${suffix}")
	pwb64=$(urlencode "$(b64 "$password")")
	url="http://$(base):801/eportal/portal/login?user_account=${acct}&user_password=${pwb64}"
	raw=$(fetch "$url" "$BIND")
	json=$(strip_jsonp "$raw")
	result=$(jsonfilter -s "$json" -e '@.result' 2>/dev/null)
	msg=$(jsonfilter -s "$json" -e '@.msg' 2>/dev/null)
	json_add_int result "${result:-0}"
	json_add_string msg "${msg:-登录请求失败（检查网络/服务器地址）}"
	json_dump
}

cmd_logout() {
	local id="$1" raw json result msg
	line_exists "$id" || { bad_line "$id"; return; }
	json_init
	json_add_int ts "$(date +%s)"
	json_add_string id "$id"
	if ! resolve_bind "$id"; then
		json_add_int result 0
		json_add_string msg "$ERR"
		json_dump; return
	fi
	raw=$(fetch "http://$(base):801/eportal/portal/logout" "$BIND")
	json=$(strip_jsonp "$raw")
	result=$(jsonfilter -s "$json" -e '@.result' 2>/dev/null)
	msg=$(jsonfilter -s "$json" -e '@.msg' 2>/dev/null)
	json_add_int result "${result:-0}"
	json_add_string msg "${msg:-注销请求失败}"
	json_dump
}

reauth_one() {
	local id="$1" st
	st=$(query_state "$id")
	if [ "$st" = "online" ]; then
		cmd_logout "$id" >/dev/null 2>&1
		sleep 1
	fi
	cmd_login "$id" >/dev/null 2>&1
	logger -t "$TAG" "re-auth [$id] finished (was: $st, now: $(line_state "$id"))"
}

# 页面「重新认证」：注销（若在线）→ 隔 1s → 登录，输出登录结果 JSON
cmd_relogin() {
	local id="$1"
	line_exists "$id" || { bad_line "$id"; return; }
	exec 9>"$LOCK"; lock_fd
	if [ "$(query_state "$id")" = "online" ]; then
		cmd_logout "$id" >/dev/null 2>&1
		sleep 1
	fi
	logger -t "$TAG" "manual re-auth [$id]"
	cmd_login "$id"
}

cmd_reauth() {
	local id
	exec 9>"$LOCK"; lock_fd
	if [ -n "$1" ]; then
		line_exists "$1" && reauth_one "$1"
	else
		logger -t "$TAG" "scheduled re-auth start"
		for id in $(line_ids); do reauth_one "$id"; done
	fi
}

# 离线（认证服务器可达但未登录）→ 自动登录；
# 认证在线但外网不通（运营商侧会话失效）→ 注销后重新登录；
# 认证服务器不可达 / 外网无法判断 → 不动作；
# 处理完后再按外网健康决定是否从多路聚合中摘除 / 加回
cmd_watchdog() {
	local id st
	exec 9>"$LOCK"; lock_fd
	fo_gc
	for id in $(line_ids); do
		st=$(query_state "$id")
		case "$st" in
		offline)
			cmd_login "$id" >/dev/null 2>&1
			logger -t "$TAG" "watchdog: [$id] was offline, relogin -> $(line_state "$id")"
			;;
		online)
			if probe_on && resolve_bind "$id" && net_down "$BIND"; then
				logger -t "$TAG" "watchdog: [$id] portal online but internet unreachable, re-auth"
				reauth_one "$id"
			fi
			;;
		esac
		failover_on || continue
		[ -n "$(lget "$id" iface)" ] || continue
		line_health "$id"
		case $? in 0) fo_ok "$id" ;; 1) fo_mark "$id" ;; esac
	done
}

# 文件锁：避免定时重授权与掉线检测同时执行（flock 不可用则跳过加锁）
# 注：BusyBox flock 不支持 -w 超时；每次请求自带 8s 超时，持锁时间有上限
lock_fd() { command -v flock >/dev/null 2>&1 && flock -x 9 2>/dev/null; return 0; }

# 旧版配置按需迁移（已是新版时只多一次 uci show）
migrate

# 未指定线路时取第一条（即使已禁用，保证手动操作有目标）
line="$2"
if [ -z "$line" ]; then
	line=$(uci -q show "$CFG" 2>/dev/null | sed -n "s/^${CFG}\.\([A-Za-z0-9_]*\)=line\$/\1/p" | head -n 1)
	line="${line:-main}"
fi
case "$1" in
	migrate)  ;;
	status)   cmd_status ;;
	query)    cmd_query  "$line" ;;
	login)    cmd_login  "$line" ;;
	logout)   cmd_logout "$line" ;;
	reauth)   cmd_reauth "$2" ;;
	relogin)  cmd_relogin "$line" ;;
	watchdog) cmd_watchdog ;;
	*) echo "usage: $0 {status|query [line]|login [line]|logout [line]|reauth [line]|relogin [line]|watchdog|migrate}" >&2; exit 1 ;;
esac
ZZU_EOF_BIN
chmod +x "$BIN"

# ---------- rpcd 包装 ----------
cat > "$RPCD" <<'ZZU_EOF_RPCD'
#!/bin/sh
BIN="/usr/sbin/zzucampusnetagent"
case "$1" in
	list)
		echo '{ "status": { }, "query": { "line": "str" }, "login": { "line": "str" }, "logout": { "line": "str" }, "reauth": { "line": "str" } }'
		;;
	call)
		read -r input 2>/dev/null
		[ -z "$input" ] && input='{}'
		line=$(jsonfilter -s "$input" -e '@.line' 2>/dev/null)
		# 线路 id 只允许字母数字下划线，其余一律置空（后端取第一条线路）
		case "$line" in *[!A-Za-z0-9_]*) line="" ;; esac
		case "$2" in
			status) "$BIN" status ;;
			query)  "$BIN" query  "$line" ;;
			login)  "$BIN" login  "$line" ;;
			logout) "$BIN" logout "$line" ;;
			reauth) "$BIN" relogin "$line" ;;
			*) echo '{}' ;;
		esac
		;;
esac
ZZU_EOF_RPCD
chmod +x "$RPCD"

# ---------- init.d（同步定时任务） ----------
cat > "$INITD" <<'ZZU_EOF_INITD'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
CRON="/etc/crontabs/root"
TAG="# zzucampusnetagent-reauth"
TAG_WD="# zzucampusnetagent-watchdog"

sync_cron() {
	local enabled time hour min wd iv
	enabled=$(uci -q get zzucampusnetagent.config.auto_relogin)
	time=$(uci -q get zzucampusnetagent.config.relogin_time)
	[ -z "$time" ] && time="06:00"
	hour=${time%%:*}; min=${time##*:}
	[ -z "$hour" ] && hour=6
	[ -z "$min" ]  && min=0
	hour=$(printf '%d' "$hour" 2>/dev/null || echo 6)
	min=$(printf '%d' "$min" 2>/dev/null || echo 0)

	wd=$(uci -q get zzucampusnetagent.config.watchdog)
	iv=$(uci -q get zzucampusnetagent.config.watchdog_interval)
	iv=$(printf '%d' "${iv:-5}" 2>/dev/null || echo 5)
	[ "$iv" -lt 1 ] && iv=1
	[ "$iv" -gt 59 ] && iv=59

	mkdir -p /etc/crontabs
	[ -f "$CRON" ] || touch "$CRON"
	sed -i -e "\|$TAG|d" -e "\|$TAG_WD|d" "$CRON"
	if [ "$enabled" = "1" ]; then
		echo "$min $hour * * * /usr/sbin/zzucampusnetagent reauth >/dev/null 2>&1 $TAG" >> "$CRON"
	fi
	if [ "$wd" = "1" ]; then
		echo "*/$iv * * * * /usr/sbin/zzucampusnetagent watchdog >/dev/null 2>&1 $TAG_WD" >> "$CRON"
	fi
	if [ "$enabled" = "1" ] || [ "$wd" = "1" ]; then
		/etc/init.d/cron enable >/dev/null 2>&1
	fi
	/etc/init.d/cron restart >/dev/null 2>&1
}

# 旧版配置（主线路存于 config 段）迁移为 line 段
migrate() { [ -x /usr/sbin/zzucampusnetagent ] && /usr/sbin/zzucampusnetagent migrate >/dev/null 2>&1; }

start_service()  { migrate; sync_cron; }
reload_service() { sync_cron; }
boot()           { migrate; sync_cron; }

stop_service() {
	[ -f "$CRON" ] && sed -i -e "\|$TAG|d" -e "\|$TAG_WD|d" "$CRON"
	/etc/init.d/cron restart >/dev/null 2>&1
}

service_triggers() {
	procd_add_reload_trigger "zzucampusnetagent"
}
ZZU_EOF_INITD
chmod +x "$INITD"

# ---------- 菜单（服务菜单下） ----------
cat > "$MENU" <<'ZZU_EOF_MENU'
{
	"admin/services/zzucampusnetagent": {
		"title": "ZZU CampusNet Agent",
		"order": 60,
		"action": {
			"type": "view",
			"path": "zzucampusnetagent/status"
		},
		"depends": {
			"acl": [ "luci-app-zzu-campusnet-agent" ]
		}
	}
}
ZZU_EOF_MENU

# ---------- ACL ----------
cat > "$ACL" <<'ZZU_EOF_ACL'
{
	"luci-app-zzu-campusnet-agent": {
		"description": "Grant access to ZZU campus network status & auth",
		"read": {
			"ubus": {
				"luci.zzucampusnetagent": [ "status", "query", "login", "logout" ],
				"network.interface": [ "dump" ]
			},
			"uci": [ "zzucampusnetagent", "network" ]
		},
		"write": {
			"ubus": {
				"luci.zzucampusnetagent": [ "login", "logout", "reauth" ]
			},
			"uci": [ "zzucampusnetagent" ]
		}
	}
}
ZZU_EOF_ACL

# ---------- UCI 配置（缺失则建默认；升级时补齐新增项，不覆盖已有值） ----------
if [ ! -f "$CFG" ]; then
cat > "$CFG" <<'ZZU_EOF_CFG'
config zzucampusnetagent 'config'
	option baseurl '172.16.4.14'
	option auto_relogin '0'
	option relogin_time '06:00'
	option watchdog '0'
	option watchdog_interval '5'
	# 外网检测：认证在线的线路再以该线路 IP 请求 probe_url（须返回 HTTP 204），不通则判定外网不通
	option probe '1'
	# 故障线路自动摘除（配合 extras/99-multipath）：重登后仍不通的线路暂时移出多路聚合，恢复后加回
	option failover '1'
	# list probe_url 'http://connect.rom.miui.com/generate_204'

# 认证线路：每条线路以所绑定出口接口（iface）的 IP 向认证服务器登录；
# iface 留空 = 走系统默认路由（单线路时保持留空即可）；account/password 每条线路各自填写。
config line 'main'
	option enabled '1'
	option name '主线路'
	option account ''
	option password ''
	option iface ''
	option isp 'campus'

# 多线路示例（同一账号在另一个出口以其它运营商认证）：
# config line
#	option enabled '1'
#	option name '移动1'
#	option account '学号'
#	option password '密码'
#	option iface 'wancm1'
#	option isp 'cmcc'
ZZU_EOF_CFG
fi

uci -q get zzucampusnetagent.config >/dev/null 2>&1 || uci set zzucampusnetagent.config=zzucampusnetagent
add_def() { uci -q get "zzucampusnetagent.config.$1" >/dev/null 2>&1 || uci set "zzucampusnetagent.config.$1=$2"; }
add_def baseurl 172.16.4.14
add_def auto_relogin 0
add_def relogin_time 06:00
add_def watchdog 0
add_def watchdog_interval 5
uci commit zzucampusnetagent
# 旧版配置（主线路存于 config 段）迁移为 line 段 main；一条线路都没有时补一条默认线路
"$BIN" migrate >/dev/null 2>&1 || true
if ! uci -q show zzucampusnetagent | grep -q '=line$'; then
	uci set zzucampusnetagent.main=line
	uci set zzucampusnetagent.main.enabled=1
	uci set zzucampusnetagent.main.name='主线路'
	uci set zzucampusnetagent.main.isp=campus
	uci commit zzucampusnetagent
fi

# ---------- 生效 ----------
"$INITD" enable >/dev/null 2>&1 || true
"$INITD" restart >/dev/null 2>&1 || "$INITD" start >/dev/null 2>&1 || true
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache* 2>/dev/null || true
rm -rf /tmp/luci-modulecache 2>/dev/null || true

echo ""
echo "==> 完成！打开 LuCI → 顶部菜单【服务】→【ZZU CampusNet Agent】"
echo "    首次使用：在页面下方「认证线路」里填写 账号 / 密码 / 运营商 → 点【保存并应用】，再点【登录】。"
echo "    如菜单未刷新，请按 Ctrl+F5 强刷浏览器或重新登录 LuCI。"
