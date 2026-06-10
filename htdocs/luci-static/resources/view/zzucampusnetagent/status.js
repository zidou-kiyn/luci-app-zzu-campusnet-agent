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
