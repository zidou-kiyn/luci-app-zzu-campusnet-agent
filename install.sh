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
	[ -f /etc/crontabs/root ] && sed -i -e '\|zzucampusnetagent-reauth|d' -e '\|zzustatus-reauth|d' /etc/crontabs/root 2>/dev/null || true
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

var callQuery  = rpc.declare({ object: 'luci.zzucampusnetagent', method: 'query',  expect: { } });
var callLogin  = rpc.declare({ object: 'luci.zzucampusnetagent', method: 'login',  expect: { } });
var callLogout = rpc.declare({ object: 'luci.zzucampusnetagent', method: 'logout', expect: { } });

var STYLE = `
.zzu-page{max-width:980px;margin:0 auto 24px}
.zzu-alert{display:flex;align-items:center;gap:10px;padding:12px 16px;border-radius:12px;margin-bottom:16px;font-size:14px;font-weight:500;box-shadow:0 6px 18px rgba(50,50,93,.1);animation:zzuIn .22s ease}
.zzu-alert.ok{background:#e7f6ef;color:#13855f;border:1px solid #c4ecda}
.zzu-alert.err{background:#fdeaef;color:#c93a5d;border:1px solid #f7cad5}
.zzu-alert-ico{width:22px;height:22px;flex:0 0 22px;display:flex;align-items:center;justify-content:center;border-radius:50%;font-size:12px;font-weight:700;color:#fff}
.zzu-alert.ok .zzu-alert-ico{background:#19b377}
.zzu-alert.err .zzu-alert-ico{background:#ea5f7e}
.zzu-alert-txt{flex:1 1 auto;word-break:break-all}
.zzu-alert-x{cursor:pointer;font-size:20px;line-height:1;opacity:.5;padding:0 4px;flex:0 0 auto}
.zzu-alert-x:hover{opacity:1}
@keyframes zzuIn{from{opacity:0;transform:translateY(-6px)}to{opacity:1;transform:none}}
@keyframes zzuPulse{0%{box-shadow:0 0 0 0 rgba(255,255,255,.35)}70%{box-shadow:0 0 0 12px rgba(255,255,255,0)}100%{box-shadow:0 0 0 0 rgba(255,255,255,0)}}

/* 渐变横幅 */
.zzu-banner{position:relative;border-radius:16px;padding:24px 26px 54px;color:#fff;box-shadow:0 10px 28px rgba(50,50,93,.2);animation:zzuIn .25s ease}
.zzu-banner-in{display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap}
.zzu-banner-l{display:flex;align-items:center;gap:15px;min-width:0}
.zzu-badge{width:56px;height:56px;flex:0 0 56px;display:flex;align-items:center;justify-content:center;font-size:26px;font-weight:700;background:rgba(255,255,255,.2);border:1px solid rgba(255,255,255,.3);border-radius:16px}
.zzu-badge.pulse{animation:zzuPulse 2.2s infinite}
.zzu-title-row{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.zzu-title{font-size:21px;font-weight:700;letter-spacing:.3px}
.zzu-pill{font-size:11px;font-weight:600;background:rgba(255,255,255,.22);border-radius:99px;padding:3px 10px;white-space:nowrap}
.zzu-sub{font-size:12.5px;opacity:.85;margin-top:4px;word-break:break-all}
.zzu-acts{display:flex;gap:8px;flex-wrap:wrap}
.zzu-btn{cursor:pointer;background:rgba(255,255,255,.16);color:#fff;border:1px solid rgba(255,255,255,.4);border-radius:9px;padding:8px 14px;font-size:13px;font-weight:600;white-space:nowrap;transition:background .15s,transform .15s}
.zzu-btn:hover{background:rgba(255,255,255,.28)}
.zzu-btn:active{transform:translateY(1px)}
.zzu-btn.primary{background:#fff;border:none;font-weight:700;box-shadow:0 2px 8px rgba(0,0,0,.15)}
.zzu-btn.primary:hover{background:#fff;transform:translateY(-1px);box-shadow:0 5px 12px rgba(0,0,0,.2)}
.zzu-btn[disabled]{opacity:.55;cursor:default;transform:none}

/* 悬浮统计卡 */
.zzu-stats{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:-34px 18px 0;position:relative;z-index:1}
@media(max-width:860px){.zzu-stats{grid-template-columns:1fr 1fr;margin:-34px 12px 0}}
.zzu-stat{background:var(--background-color-high,#fff);border-radius:13px;padding:15px 16px;box-shadow:0 6px 18px rgba(50,50,93,.1);border:1px solid rgba(0,0,0,.04);display:flex;align-items:center;gap:12px;min-width:0}
.zzu-stat-ico{width:38px;height:38px;flex:0 0 38px;display:flex;align-items:center;justify-content:center;font-size:17px;border-radius:10px}
.zzu-stat-k{font-size:11.5px;color:#8898aa}
.zzu-stat-v{font-size:14.5px;font-weight:700;margin-top:2px;color:var(--main-color,#32325d);word-break:break-all}

/* 设置卡 */
.zzu-settings{background:var(--background-color-high,#fff);border-radius:16px;margin-top:22px;border:1px solid rgba(0,0,0,.04);box-shadow:0 8px 24px rgba(50,50,93,.08)}
.zzu-set-hd{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:18px 24px;cursor:pointer;user-select:none;font-size:15px;font-weight:700;color:var(--main-color,#32325d)}
.zzu-set-toggle{font-size:12px;font-weight:600;color:#4a5bd0;white-space:nowrap}
.zzu-set-bd{padding:0 24px 6px;border-top:1px solid rgba(0,0,0,.06)}
.zzu-set-bd .cbi-map,.zzu-set-bd .cbi-section,.zzu-set-bd .cbi-section-node{background:transparent !important;box-shadow:none !important;border:none !important;margin:0 !important;border-radius:0 !important}
.zzu-set-bd .cbi-map-descr{font-size:12px;color:#8898aa;margin:10px 0 4px;line-height:1.6}
.zzu-set-ft{display:flex;justify-content:flex-end;padding:14px 24px 20px;border-top:1px solid rgba(0,0,0,.06)}
.zzu-save{cursor:pointer;background:linear-gradient(135deg,#5e72e4,#4a5bd0);color:#fff;border:none;border-radius:9px;padding:9px 24px;font-size:13px;font-weight:600;box-shadow:0 4px 10px rgba(94,114,228,.35);transition:transform .15s,box-shadow .15s}
.zzu-save:hover{transform:translateY(-1px);box-shadow:0 6px 14px rgba(94,114,228,.45)}
.zzu-save:active{transform:translateY(0)}
.zzu-collapsed .zzu-set-bd,.zzu-collapsed .zzu-set-ft{display:none}

@media (prefers-color-scheme:dark){
.zzu-stat{background:rgba(40,44,58,.96);border-color:rgba(255,255,255,.08)}
.zzu-stat-v{color:#e8ecf3}
.zzu-settings{background:rgba(255,255,255,.04);border-color:rgba(255,255,255,.08)}
.zzu-set-hd{color:#e8ecf3}
.zzu-set-bd,.zzu-set-ft{border-color:rgba(255,255,255,.08)}
.zzu-alert.ok{background:rgba(25,179,119,.12)}
.zzu-alert.err{background:rgba(234,95,126,.12)}
}
`;

var META = {
    online:  { label: '在线',     icon: '✓', grad: 'linear-gradient(135deg,#19b377,#0e9b8f)', accent: '#0e9b8f', pulse: true },
    offline: { label: '离线',     icon: '!', grad: 'linear-gradient(135deg,#f0a13c,#e8703a)', accent: '#e8703a' },
    error:   { label: '连接异常', icon: '✕', grad: 'linear-gradient(135deg,#ea5f7e,#d2486a)', accent: '#d2486a' }
};

var STATS = [
    { key: 'account',  label: '账号',     icon: '👤', bg: '#e7f6ef' },
    { key: 'carrier',  label: '运营商',   icon: '📡', bg: '#e9f0fb' },
    { key: 'duration', label: '在线时长', icon: '⏱',  bg: '#fdf1e4' },
    { key: 'ip',       label: 'IP 地址',  icon: '🌐', bg: '#f0edfb' }
];

function fmt(v) { return (v === undefined || v === null || v === '') ? '—' : v; }

return view.extend({
    handleRefresh: function() { return this.refresh(); },

    handleLogin: function() {
        var self = this;
        return callLogin().then(function(r) {
            r = r || {};
            self.showMsg(r.result == 1, (r.result == 1 ? '登录成功：' : '登录未成功：') + fmt(r.msg));
            return self.refresh();
        }).catch(function() { self.showMsg(false, '登录请求异常'); });
    },

    handleLogout: function() {
        var self = this;
        return callLogout().then(function(r) {
            r = r || {};
            self.showMsg(r.result == 1, (r.result == 1 ? '注销成功：' : '注销未成功：') + fmt(r.msg));
            return self.refresh();
        }).catch(function() { self.showMsg(false, '注销请求异常'); });
    },

    // 内联提示条：可手动关闭 + 6 秒自动消失
    showMsg: function(ok, text) {
        var box = document.getElementById('zzu-msg');
        if (!box) return;
        var closer = E('span', { 'class': 'zzu-alert-x' }, '×');
        var alert = E('div', { 'class': 'zzu-alert ' + (ok ? 'ok' : 'err') }, [
            E('span', { 'class': 'zzu-alert-ico' }, ok ? '✓' : '✕'),
            E('span', { 'class': 'zzu-alert-txt' }, text),
            closer
        ]);
        var remove = function() { if (alert && alert.parentNode) alert.parentNode.removeChild(alert); };
        closer.addEventListener('click', remove);
        dom.content(box, alert);
        window.setTimeout(remove, 6000);
    },

    refresh: function() {
        var self = this;
        return callQuery().then(function(res) {
            self.update(res || {});
        }).catch(function(e) {
            self.update({ status: 'error', msg: '后端调用失败：' + (e && e.message ? e.message : e) });
        });
    },

    update: function(res) {
        var root = document.getElementById('zzu-root');
        if (root) dom.content(root, this.renderStatus(res));
    },

    // 横幅 + 悬浮统计卡
    renderStatus: function(res) {
        res = res || {};
        var st = res.status || 'error';
        var m = META[st] || META.error;
        var ts = res.ts ? new Date(res.ts * 1000) : new Date();

        var banner = E('div', { 'class': 'zzu-banner', 'style': 'background:' + m.grad }, [
            E('div', { 'class': 'zzu-banner-in' }, [
                E('div', { 'class': 'zzu-banner-l' }, [
                    E('div', { 'class': 'zzu-badge' + (m.pulse ? ' pulse' : '') }, m.icon),
                    E('div', { 'style': 'min-width:0' }, [
                        E('div', { 'class': 'zzu-title-row' }, [
                            E('span', { 'class': 'zzu-title' }, m.label),
                            E('span', { 'class': 'zzu-pill' }, '每 10 秒自动刷新')
                        ]),
                        E('div', { 'class': 'zzu-sub' },
                            fmt(res.msg) + ' · 最近更新 ' + ts.toLocaleTimeString())
                    ])
                ]),
                E('div', { 'class': 'zzu-acts' }, [
                    E('button', { 'class': 'zzu-btn', 'click': ui.createHandlerFn(this, 'handleRefresh') }, '⟳ 刷新'),
                    E('button', {
                        'class': 'zzu-btn primary',
                        'style': 'color:' + m.accent,
                        'click': ui.createHandlerFn(this, 'handleLogin')
                    }, '🔑 登录'),
                    E('button', { 'class': 'zzu-btn', 'click': ui.createHandlerFn(this, 'handleLogout') }, '⏻ 注销')
                ])
            ])
        ]);

        var stats = E('div', { 'class': 'zzu-stats' }, STATS.map(function(s) {
            return E('div', { 'class': 'zzu-stat' }, [
                E('div', { 'class': 'zzu-stat-ico', 'style': 'background:' + s.bg }, s.icon),
                E('div', { 'style': 'min-width:0' }, [
                    E('div', { 'class': 'zzu-stat-k' }, s.label),
                    E('div', { 'class': 'zzu-stat-v' }, st === 'online' ? fmt(res[s.key]) : '—')
                ])
            ]);
        }));

        return [ banner, stats ];
    },

    load: function() {
        return callQuery().then(function(r) { return r || {}; }).catch(function() {
            return { status: 'error', msg: '后端调用失败' };
        });
    },

    // 保存按钮内置在设置卡片右下角，隐藏默认页脚
    addFooter: function() { return E([]); },

    render: function(data) {
        var self = this;

        var m = new form.Map('zzucampusnetagent', null,
            '修改账号、密码、运营商和服务器地址后请点击右下角"保存并应用"。手动"登录/注销"使用的是已保存的配置。');
        var s = m.section(form.NamedSection, 'config', 'zzucampusnetagent');
        var o;

        o = s.option(form.Value, 'baseurl', '服务器地址 (Base URL)', '认证服务器地址，默认 172.16.4.14，无需带 http:// 与端口');
        o.placeholder = '172.16.4.14';
        o.default = '172.16.4.14';

        o = s.option(form.Value, 'account', '账号', '学号 / 账号，不含运营商后缀（如 @cmcc）');
        o.placeholder = '请输入账号';

        o = s.option(form.Value, 'password', '密码', '明文填写，后台自动 base64 编码后提交');
        o.password = true;

        o = s.option(form.ListValue, 'isp', '运营商');
        o.value('campus', '校园网 (无后缀)');
        o.value('cmcc', '中国移动 (@cmcc)');
        o.value('unicom', '中国联通 (@unicom)');
        o.value('telecom', '中国电信 (@telecom)');
        o.value('zzuplan', '学科专网 (@zzuplan)');
        o.default = 'campus';

        o = s.option(form.Flag, 'auto_relogin', '每天定时重新授权',
            '到点若在线则先注销，间隔 1 秒后重新登录，保证授权不掉线');
        o.default = '0';
        o.rmempty = false;

        o = s.option(form.Value, 'relogin_time', '定时时间', '24 小时制 HH:MM，默认 06:00（凌晨 6 点）');
        o.placeholder = '06:00';
        o.default = '06:00';
        o.depends('auto_relogin', '1');

        return m.render().then(function(mapEl) {
            poll.add(function() { return self.refresh(); }, 10);

            var toggle = E('span', { 'class': 'zzu-set-toggle' }, '收起 ▴');
            var settings = E('div', { 'class': 'zzu-settings' }, [
                E('div', {
                    'class': 'zzu-set-hd',
                    'click': function() {
                        var card = this.parentNode;
                        var collapsed = card.classList.toggle('zzu-collapsed');
                        toggle.textContent = collapsed ? '展开 ▾' : '收起 ▴';
                    }
                }, [
                    E('span', {}, '⚙ 账号与认证设置'),
                    toggle
                ]),
                E('div', { 'class': 'zzu-set-bd' }, mapEl),
                E('div', { 'class': 'zzu-set-ft' }, [
                    E('button', {
                        'class': 'zzu-save',
                        'click': ui.createHandlerFn(self, 'handleSaveApply', '0')
                    }, '保存并应用')
                ])
            ]);

            return E('div', { 'class': 'zzu-page' }, [
                E('style', { 'type': 'text/css' }, STYLE),
                E('div', { 'id': 'zzu-msg' }),
                E('div', { 'id': 'zzu-root' }, self.renderStatus(data)),
                settings
            ]);
        });
    }
});
ZZU_EOF_JS

# ---------- 核心 CLI ----------
cat > "$BIN" <<'ZZU_EOF_BIN'
#!/bin/sh
# zzucampusnetagent - 郑大校园网 eportal 命令行核心
# 用法: zzucampusnetagent {query|login|logout|reauth}
. /usr/share/libubox/jshn.sh

CFG="zzucampusnetagent"
cfg() { uci -q get "${CFG}.config.$1" 2>/dev/null; }
base() { local b; b=$(cfg baseurl); echo "${b:-172.16.4.14}"; }

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

fetch() {
	local ref ua
	ref="http://$(base)/"
	ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
	if command -v curl >/dev/null 2>&1; then
		curl -s --max-time 8 -A "$ua" -e "$ref" "$1" 2>/dev/null
	elif command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -q -T 8 -U "$ua" -O - "$1" 2>/dev/null
	else
		wget -q -O - "$1" 2>/dev/null
	fi
}

strip_jsonp() { echo "$1" | sed -e 's/^[^(]*(//' -e 's/)[^)]*$//'; }

cmd_query() {
	local raw json result msg
	raw=$(fetch "http://$(base):801/eportal/portal/custom")
	json_init
	json_add_int ts "$(date +%s)"
	if [ -z "$raw" ]; then
		json_add_string status "error"
		json_add_string msg "无法连接认证服务器（确认路由器已接入校园网）"
		json_dump; return
	fi
	json=$(strip_jsonp "$raw")
	result=$(jsonfilter -s "$json" -e '@.result' 2>/dev/null)
	msg=$(jsonfilter -s "$json" -e '@.msg' 2>/dev/null)
	if [ "$result" = "1" ]; then
		json_add_string status "online"
		json_add_string msg "${msg:-在线}"
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
	json_dump
}

query_state() {
	local raw json
	raw=$(fetch "http://$(base):801/eportal/portal/custom")
	[ -z "$raw" ] && { echo "error"; return; }
	json=$(strip_jsonp "$raw")
	case "$(jsonfilter -s "$json" -e '@.result' 2>/dev/null)" in
		1) echo "online" ;; 0) echo "offline" ;; *) echo "error" ;;
	esac
}

cmd_login() {
	local account password isp suffix acct pwb64 url raw json result msg
	account=$(cfg account); password=$(cfg password); isp=$(cfg isp)
	suffix=$(isp_suffix "$isp")
	json_init
	json_add_int ts "$(date +%s)"
	if [ -z "$account" ] || [ -z "$password" ]; then
		json_add_int result 0
		json_add_string msg "请先在下方设置账号和密码并保存"
		json_dump; return
	fi
	acct=$(urlencode ",0,${account}${suffix}")
	pwb64=$(urlencode "$(b64 "$password")")
	url="http://$(base):801/eportal/portal/login?user_account=${acct}&user_password=${pwb64}"
	raw=$(fetch "$url")
	json=$(strip_jsonp "$raw")
	result=$(jsonfilter -s "$json" -e '@.result' 2>/dev/null)
	msg=$(jsonfilter -s "$json" -e '@.msg' 2>/dev/null)
	json_add_int result "${result:-0}"
	json_add_string msg "${msg:-登录请求失败（检查网络/服务器地址）}"
	json_dump
}

cmd_logout() {
	local raw json result msg
	raw=$(fetch "http://$(base):801/eportal/portal/logout")
	json=$(strip_jsonp "$raw")
	result=$(jsonfilter -s "$json" -e '@.result' 2>/dev/null)
	msg=$(jsonfilter -s "$json" -e '@.msg' 2>/dev/null)
	json_init
	json_add_int ts "$(date +%s)"
	json_add_int result "${result:-0}"
	json_add_string msg "${msg:-注销请求失败}"
	json_dump
}

cmd_reauth() {
	local st
	logger -t zzucampusnetagent "scheduled re-auth start"
	st=$(query_state)
	if [ "$st" = "online" ]; then
		cmd_logout >/dev/null 2>&1
		logger -t zzucampusnetagent "logout done, sleep 1s then login"
		sleep 1
	fi
	cmd_login >/dev/null 2>&1
	logger -t zzucampusnetagent "scheduled re-auth finished (was: $st)"
}

case "$1" in
	query)  cmd_query ;;
	login)  cmd_login ;;
	logout) cmd_logout ;;
	reauth) cmd_reauth ;;
	*) echo "usage: $0 {query|login|logout|reauth}" >&2; exit 1 ;;
esac
ZZU_EOF_BIN
chmod +x "$BIN"

# ---------- rpcd 包装 ----------
cat > "$RPCD" <<'ZZU_EOF_RPCD'
#!/bin/sh
BIN="/usr/sbin/zzucampusnetagent"
case "$1" in
	list)
		echo '{ "query": { }, "login": { }, "logout": { } }'
		;;
	call)
		read -r _ 2>/dev/null
		case "$2" in
			query)  "$BIN" query ;;
			login)  "$BIN" login ;;
			logout) "$BIN" logout ;;
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

sync_cron() {
	local enabled time hour min
	enabled=$(uci -q get zzucampusnetagent.config.auto_relogin)
	time=$(uci -q get zzucampusnetagent.config.relogin_time)
	[ -z "$time" ] && time="06:00"
	hour=${time%%:*}; min=${time##*:}
	[ -z "$hour" ] && hour=6
	[ -z "$min" ]  && min=0
	hour=$(printf '%d' "$hour" 2>/dev/null || echo 6)
	min=$(printf '%d' "$min" 2>/dev/null || echo 0)
	mkdir -p /etc/crontabs
	[ -f "$CRON" ] || touch "$CRON"
	sed -i "\|$TAG|d" "$CRON"
	if [ "$enabled" = "1" ]; then
		echo "$min $hour * * * /usr/sbin/zzucampusnetagent reauth >/dev/null 2>&1 $TAG" >> "$CRON"
		/etc/init.d/cron enable >/dev/null 2>&1
	fi
	/etc/init.d/cron restart >/dev/null 2>&1
}

start_service()  { sync_cron; }
reload_service() { sync_cron; }
boot()           { sync_cron; }

stop_service() {
	[ -f "$CRON" ] && sed -i "\|$TAG|d" "$CRON"
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
				"luci.zzucampusnetagent": [ "query", "login", "logout" ]
			},
			"uci": [ "zzucampusnetagent" ]
		},
		"write": {
			"ubus": {
				"luci.zzucampusnetagent": [ "login", "logout" ]
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
	option account ''
	option password ''
	option isp 'campus'
	option auto_relogin '0'
	option relogin_time '06:00'
ZZU_EOF_CFG
fi

uci -q get zzucampusnetagent.config >/dev/null 2>&1 || uci set zzucampusnetagent.config=zzucampusnetagent
add_def() { uci -q get "zzucampusnetagent.config.$1" >/dev/null 2>&1 || uci set "zzucampusnetagent.config.$1=$2"; }
add_def baseurl 172.16.4.14
add_def isp campus
add_def auto_relogin 0
add_def relogin_time 06:00
uci commit zzucampusnetagent

# ---------- 生效 ----------
"$INITD" enable >/dev/null 2>&1 || true
"$INITD" restart >/dev/null 2>&1 || "$INITD" start >/dev/null 2>&1 || true
/etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache* 2>/dev/null || true
rm -rf /tmp/luci-modulecache 2>/dev/null || true

echo ""
echo "==> 完成！打开 LuCI → 顶部菜单【服务】→【ZZU CampusNet Agent】"
echo "    首次使用：在页面下方填写 账号 / 密码 / 运营商 → 点【保存并应用】，再点【🔑 登录】。"
echo "    如菜单未刷新，请按 Ctrl+F5 强刷浏览器或重新登录 LuCI。"
