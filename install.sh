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

var STYLE = `
.zzu-page{max-width:980px;margin:0 auto 24px}
.zzu-line{margin-bottom:22px}
.zzu-line:last-child{margin-bottom:0}
.zzu-set-bd .cbi-section-table{margin-top:6px}
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

var ISPS = [
    [ 'campus',  '校园网 (无后缀)' ],
    [ 'cmcc',    '中国移动 (@cmcc)' ],
    [ 'unicom',  '中国联通 (@unicom)' ],
    [ 'telecom', '中国电信 (@telecom)' ],
    [ 'zzuplan', '学科专网 (@zzuplan)' ]
];

function fmt(v) { return (v === undefined || v === null || v === '') ? '—' : v; }

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
        return callStatus().then(function(res) {
            self.update(res || {});
        }).catch(function(e) {
            self.update({ lines: [ { id: 'main', status: 'error', msg: '后端调用失败：' + (e && e.message ? e.message : e) } ] });
        });
    },

    update: function(res) {
        var root = document.getElementById('zzu-root');
        if (root) dom.content(root, this.renderAll(res));
    },

    renderAll: function(res) {
        var self = this;
        res = res || {};
        var lines = Array.isArray(res.lines) && res.lines.length ? res.lines : [ { id: 'main', status: 'error', msg: '无线路数据' } ];
        this.lines = lines;
        return lines.map(function(l) {
            return E('div', { 'class': 'zzu-line' }, self.renderLine(l, res.ts, lines.length > 1));
        });
    },

    // 单条线路：横幅 + 悬浮统计卡
    renderLine: function(res, tsv, multi) {
        res = res || {};
        var st = res.status || 'error';
        var m = META[st] || META.error;
        var ts = tsv ? new Date(tsv * 1000) : new Date();
        var id = res.id || 'main';
        var pill = res.iface ? ('接口 ' + res.iface + (res.bind ? ' · ' + res.bind : '')) : '默认路由';
        var title = multi ? (fmt(res.name) + ' · ' + m.label) : m.label;

        var banner = E('div', { 'class': 'zzu-banner', 'style': 'background:' + m.grad }, [
            E('div', { 'class': 'zzu-banner-in' }, [
                E('div', { 'class': 'zzu-banner-l' }, [
                    E('div', { 'class': 'zzu-badge' + (m.pulse ? ' pulse' : '') }, m.icon),
                    E('div', { 'style': 'min-width:0' }, [
                        E('div', { 'class': 'zzu-title-row' }, [
                            E('span', { 'class': 'zzu-title' }, title),
                            E('span', { 'class': 'zzu-pill' }, multi ? pill : '每 10 秒自动刷新')
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
                        'click': ui.createHandlerFn(this, 'handleLogin', id)
                    }, '🔑 登录'),
                    E('button', { 'class': 'zzu-btn', 'click': ui.createHandlerFn(this, 'handleLogout', id) }, '⏻ 注销')
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
        return callStatus().then(function(r) { return r || {}; }).catch(function() {
            return { lines: [ { id: 'main', status: 'error', msg: '后端调用失败' } ] };
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

        o = s.option(form.Value, 'account', '账号', '学号 / 账号，不含运营商后缀（如 @cmcc）；所有线路共用');
        o.placeholder = '请输入账号';

        o = s.option(form.Value, 'password', '密码', '明文填写，后台自动 base64 编码后提交');
        o.password = true;

        o = s.option(form.Value, 'name', '主线路名称');
        o.placeholder = '主线路';

        o = s.option(widgets.NetworkSelect, 'iface', '主线路出口接口',
            '留空 = 走系统默认路由（单线路时保持留空即可）');
        o.nocreate = true;
        o.optional = true;
        o.rmempty = true;

        o = s.option(form.ListValue, 'isp', '主线路运营商');
        addIsp(o);

        o = s.option(form.Flag, 'auto_relogin', '每天定时重新授权',
            '到点对所有线路执行：若在线则先注销，间隔 1 秒后重新登录，保证授权不掉线');
        o.default = '0';
        o.rmempty = false;

        o = s.option(form.Value, 'relogin_time', '定时时间', '24 小时制 HH:MM，默认 06:00（凌晨 6 点）');
        o.placeholder = '06:00';
        o.default = '06:00';
        o.depends('auto_relogin', '1');

        o = s.option(form.Flag, 'watchdog', '掉线自动重登',
            '定期检查所有线路，发现未登录（认证服务器可达但离线）时自动重新登录');
        o.default = '0';
        o.rmempty = false;

        o = s.option(form.Value, 'watchdog_interval', '检查间隔（分钟）', '1–59，默认 5');
        o.datatype = 'range(1,59)';
        o.placeholder = '5';
        o.default = '5';
        o.depends('watchdog', '1');

        // 额外线路：同一账号在其它出口（如 macvlan 虚拟 WAN）以其它运营商认证
        var ls = m.section(form.TableSection, 'line', '额外线路',
            '同一账号可在不同出口同时登录不同运营商。每条线路需绑定一个已获取到校园网 IP 的接口（例如 macvlan 虚拟 WAN）。');
        ls.anonymous = true;
        ls.addremove = true;
        ls.addbtntitle = '添加线路';

        o = ls.option(form.Flag, 'enabled', '启用');
        o.default = '1';
        o.rmempty = false;

        o = ls.option(form.Value, 'name', '名称');
        o.placeholder = '如：移动1';

        o = ls.option(widgets.NetworkSelect, 'iface', '出口接口');
        o.nocreate = true;
        o.rmempty = false;

        o = ls.option(form.ListValue, 'isp', '运营商');
        addIsp(o);

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
                E('div', { 'id': 'zzu-root' }, self.renderAll(data)),
                settings
            ]);
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
#   zzucampusnetagent query  [线路]       查询单条线路（默认 main）
#   zzucampusnetagent login  [线路]       登录单条线路（默认 main）
#   zzucampusnetagent logout [线路]       注销单条线路（默认 main）
#   zzucampusnetagent reauth [线路]       注销→隔1s→登录；不带参数则对全部线路执行
#   zzucampusnetagent watchdog            检查全部线路，离线的自动重新登录
#
# 线路: "main" 为主线路（UCI 的 config 段），其余为 UCI 中类型为 line 的段名。
# 每条线路可绑定一个 netifd 逻辑接口（iface），请求会以该接口的 IP 为源地址发出，
# 从而让同一账号在不同出口上分别以不同运营商认证。
. /usr/share/libubox/jshn.sh
. /lib/functions/network.sh

CFG="zzucampusnetagent"
TAG="zzucampusnetagent"
LOCK="/var/lock/zzucampusnetagent.lock"

cfg() { uci -q get "${CFG}.config.$1" 2>/dev/null; }
base() { local b; b=$(cfg baseurl); echo "${b:-172.16.4.14}"; }

# 线路 id 合法性（防注入）：只允许字母数字下划线
valid_id() { case "$1" in ""|*[!A-Za-z0-9_]*) return 1 ;; esac; return 0; }

# 读取线路属性：main → config 段，其它 → 同名 line 段
lget() {
	if [ "$1" = "main" ]; then cfg "$2"
	else uci -q get "${CFG}.$1.$2" 2>/dev/null; fi
}

line_exists() {
	[ "$1" = "main" ] && return 0
	valid_id "$1" || return 1
	[ "$(uci -q get "${CFG}.$1" 2>/dev/null)" = "line" ]
}

# 列出全部已启用线路（main 永远在第一个）
line_ids() {
	local id
	echo main
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

# 向当前 json 对象写入线路查询结果字段
add_query_fields() {
	local id="$1" raw json result msg
	json_add_string id    "$id"
	json_add_string name  "$(line_name "$id")"
	json_add_string iface "$(lget "$id" iface)"
	json_add_string isp   "$(lget "$id" isp)"
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

cmd_status() {
	local id
	json_init
	json_add_int ts "$(date +%s)"
	json_add_array lines
	for id in $(line_ids); do
		json_add_object ""
		add_query_fields "$id"
		json_close_object
	done
	json_close_array
	json_dump
}

cmd_login() {
	local id="$1" account password suffix acct pwb64 url raw json result msg
	line_exists "$id" || { bad_line "$id"; return; }
	account=$(cfg account); password=$(cfg password)
	suffix=$(isp_suffix "$(lget "$id" isp)")
	json_init
	json_add_int ts "$(date +%s)"
	json_add_string id "$id"
	if [ -z "$account" ] || [ -z "$password" ]; then
		json_add_int result 0
		json_add_string msg "请先在下方设置账号和密码并保存"
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
	logger -t "$TAG" "re-auth [$id] finished (was: $st, now: $(query_state "$id"))"
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

# 离线（认证服务器可达但未登录）→ 自动登录；服务器不可达则不动作
cmd_watchdog() {
	local id st
	exec 9>"$LOCK"; lock_fd
	for id in $(line_ids); do
		st=$(query_state "$id")
		[ "$st" = "offline" ] || continue
		cmd_login "$id" >/dev/null 2>&1
		logger -t "$TAG" "watchdog: [$id] was offline, relogin -> $(query_state "$id")"
	done
}

# 文件锁：避免定时重授权与掉线检测同时执行（flock 不可用则跳过加锁）
# 注：BusyBox flock 不支持 -w 超时；每次请求自带 8s 超时，持锁时间有上限
lock_fd() { command -v flock >/dev/null 2>&1 && flock -x 9 2>/dev/null; return 0; }

line="${2:-main}"
case "$1" in
	status)   cmd_status ;;
	query)    cmd_query  "$line" ;;
	login)    cmd_login  "$line" ;;
	logout)   cmd_logout "$line" ;;
	reauth)   cmd_reauth "$2" ;;
	watchdog) cmd_watchdog ;;
	*) echo "usage: $0 {status|query [line]|login [line]|logout [line]|reauth [line]|watchdog}" >&2; exit 1 ;;
esac
ZZU_EOF_BIN
chmod +x "$BIN"

# ---------- rpcd 包装 ----------
cat > "$RPCD" <<'ZZU_EOF_RPCD'
#!/bin/sh
BIN="/usr/sbin/zzucampusnetagent"
case "$1" in
	list)
		echo '{ "status": { }, "query": { "line": "str" }, "login": { "line": "str" }, "logout": { "line": "str" } }'
		;;
	call)
		read -r input 2>/dev/null
		[ -z "$input" ] && input='{}'
		line=$(jsonfilter -s "$input" -e '@.line' 2>/dev/null)
		# 线路 id 只允许字母数字下划线，其余一律按主线路处理
		case "$line" in ""|*[!A-Za-z0-9_]*) line="main" ;; esac
		case "$2" in
			status) "$BIN" status ;;
			query)  "$BIN" query  "$line" ;;
			login)  "$BIN" login  "$line" ;;
			logout) "$BIN" logout "$line" ;;
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

start_service()  { sync_cron; }
reload_service() { sync_cron; }
boot()           { sync_cron; }

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
	option name '主线路'
	option iface ''
	option isp 'campus'
	option auto_relogin '0'
	option relogin_time '06:00'
	option watchdog '0'
	option watchdog_interval '5'

# 额外线路示例（同一账号在另一个出口以其它运营商认证）：
# config line
#	option enabled '1'
#	option name '移动1'
#	option iface 'wancm1'
#	option isp 'cmcc'
ZZU_EOF_CFG
fi

uci -q get zzucampusnetagent.config >/dev/null 2>&1 || uci set zzucampusnetagent.config=zzucampusnetagent
add_def() { uci -q get "zzucampusnetagent.config.$1" >/dev/null 2>&1 || uci set "zzucampusnetagent.config.$1=$2"; }
add_def baseurl 172.16.4.14
add_def isp campus
add_def auto_relogin 0
add_def relogin_time 06:00
add_def watchdog 0
add_def watchdog_interval 5
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
