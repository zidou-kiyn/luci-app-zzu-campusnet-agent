'use strict';
'require view';
'require form';
'require rpc';
'require poll';
'require dom';
'require ui';
'require uci';
'require tools.widgets as widgets';

var callDays    = rpc.declare({ object: 'luci.zzucampusnetagent', method: 'netmon_days', expect: { } });
var callDevices = rpc.declare({ object: 'luci.zzucampusnetagent', method: 'netmon_devices', params: [ 'day' ], expect: { } });
var callDomains = rpc.declare({ object: 'luci.zzucampusnetagent', method: 'netmon_domains', params: [ 'id', 'day' ], expect: { } });
var callAlias   = rpc.declare({ object: 'luci.zzucampusnetagent', method: 'netmon_alias', params: [ 'id', 'name' ], expect: { } });

var STYLE = `
.zzm{max-width:1100px}
.zzm-bar{display:flex;flex-wrap:wrap;align-items:center;gap:10px 18px;margin:6px 0 14px}
.zzm-bar select{min-width:190px}
.zzm-sum{color:#666;font-size:13px}
.zzm-sum b{color:inherit;font-size:14px}
.zzm-note{margin:0 0 14px;padding:10px 14px;border-radius:8px;background:rgba(94,114,228,.08);font-size:12.5px;line-height:1.7}
.zzm table{width:100%}
.zzm td,.zzm th{vertical-align:middle}
.zzm .num{text-align:right;white-space:nowrap;font-variant-numeric:tabular-nums}
.zzm .sub{display:block;font-size:11.5px;opacity:.65;font-family:monospace}
.zzm .rate{font-size:12px;white-space:nowrap;font-variant-numeric:tabular-nums}
.zzm .dn{color:#19b377}.zzm .up{color:#f0a13c}
.zzm-bar-bg{height:4px;border-radius:2px;background:rgba(127,127,127,.15);margin-top:4px}
.zzm-bar-fg{height:4px;border-radius:2px;background:#5e72e4}
.zzm-empty{padding:30px;text-align:center;opacity:.7}
.zzm-dlg-ctl{display:flex;flex-wrap:wrap;gap:10px 16px;align-items:center;margin-bottom:10px}
.zzm-dlg-ctl input[type=text]{flex:1;min-width:180px}
.zzm-dlg-list{max-height:60vh;overflow:auto}
.zzm-dlg-list td{padding:4px 8px}
`;

// 二级后缀：按主域名合并时 a.b.com.cn → b.com.cn
var SLD = { 'com.cn': 1, 'net.cn': 1, 'org.cn': 1, 'gov.cn': 1, 'edu.cn': 1, 'ac.cn': 1,
            'com.hk': 1, 'com.tw': 1, 'co.uk': 1, 'co.jp': 1, 'com.au': 1, 'com.sg': 1 };

function baseDomain(d) {
    var p = d.split('.');
    if (p.length <= 2) return d;
    return SLD[p.slice(-2).join('.')] ? p.slice(-3).join('.') : p.slice(-2).join('.');
}

function fmtBytes(b) {
    b = +b || 0;
    var u = [ 'B', 'KB', 'MB', 'GB', 'TB' ], i = 0;
    while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
    return (i ? b.toFixed(b < 10 ? 2 : 1) : b) + ' ' + u[i];
}

function fmtRate(bytesPerSec) {
    var bits = (bytesPerSec || 0) * 8;
    if (bits >= 1e6) return (bits / 1e6).toFixed(bits >= 1e8 ? 0 : 1) + ' Mbps';
    if (bits >= 1e3) return (bits / 1e3).toFixed(0) + ' Kbps';
    return bits > 0 ? '<1 Kbps' : '0';
}

function fmtDay(d, today) {
    var s = d.substr(0, 4) + '-' + d.substr(4, 2) + '-' + d.substr(6, 2);
    return d === today ? s + '（今天）' : s;
}

function isMac(id) { return /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/.test(id || ''); }

return view.extend({
    day: null,
    today: null,
    prev: {},      // id → { cdl, cul, ts }，算实时速率
    rates: {},

    load: function() {
        return Promise.all([
            callDays().catch(function() { return {}; }),
            uci.load('zzucampusnetagent')
        ]);
    },

    refresh: function() {
        var self = this;
        return callDevices(this.day).then(function(r) {
            self.update(r || {});
        }).catch(function(e) {
            dom.content(document.getElementById('zzm-table'),
                E('div', { 'class': 'zzm-empty' }, [ '读取失败：' + (e && e.message ? e.message : e) ]));
        });
    },

    // 用相邻两次轮询的原始计数器差值算速率（只有当天、且设备当前有计数时才有）
    calcRates: function(r) {
        var self = this, now = {};
        (r.devices || []).forEach(function(d) {
            if (d.cdl === undefined) return;
            var p = self.prev[d.id];
            if (p && r.ts > p.ts) {
                var dt = r.ts - p.ts;
                self.rates[d.id] = {
                    dl: Math.max(0, d.cdl - p.cdl) / dt,
                    ul: Math.max(0, d.cul - p.cul) / dt
                };
            }
            now[d.id] = { cdl: d.cdl, cul: d.cul, ts: r.ts };
        });
        this.prev = now;
    },

    update: function(r) {
        var self = this;
        var devs = (r.devices || []).filter(function(d) { return d.rx > 0 || d.tx > 0 || d.domains > 0; });
        if (r.live) this.calcRates(r); else this.rates = {};
        devs.sort(function(a, b) { return (b.rx + b.tx) - (a.rx + a.tx); });

        var trx = 0, ttx = 0, max = 1;
        devs.forEach(function(d) { trx += d.rx; ttx += d.tx; max = Math.max(max, d.rx + d.tx); });
        dom.content(document.getElementById('zzm-sum'), [
            E('b', {}, [ devs.length + ' 台设备' ]), '　合计 ↓ ', E('b', {}, [ fmtBytes(trx) ]),
            '　↑ ', E('b', {}, [ fmtBytes(ttx) ]),
            r.live ? '　（每 5 秒刷新）' : ''
        ]);

        if (!devs.length) {
            var on = uci.get('zzucampusnetagent', 'netmon', 'enabled') === '1';
            dom.content(document.getElementById('zzm-table'), E('div', { 'class': 'zzm-empty' }, [
                on ? '这一天还没有数据（流量每 5 分钟汇总一次）' : '设备监控未开启：在下方设置中勾选「启用」并保存'
            ]));
            return;
        }

        var rows = devs.map(function(d) {
            var rt = self.rates[d.id];
            var nameCell = [ d.name || (isMac(d.id) ? '未知设备' : d.id), E('span', { 'class': 'sub' }, [ isMac(d.id) ? d.id : '（无 MAC）' ]) ];
            var pct = Math.round((d.rx + d.tx) * 100 / max);
            return E('tr', { 'class': 'tr' }, [
                E('td', { 'class': 'td' }, nameCell),
                E('td', { 'class': 'td' }, [ d.ip || '—' ]),
                E('td', { 'class': 'td rate' }, r.live ? [
                    E('span', { 'class': 'dn' }, [ '↓ ' + (rt ? fmtRate(rt.dl) : '…') ]), E('br'),
                    E('span', { 'class': 'up' }, [ '↑ ' + (rt ? fmtRate(rt.ul) : '…') ])
                ] : [ '—' ]),
                E('td', { 'class': 'td num' }, [ fmtBytes(d.rx),
                    E('div', { 'class': 'zzm-bar-bg' }, [ E('div', { 'class': 'zzm-bar-fg', 'style': 'width:' + pct + '%' }) ]) ]),
                E('td', { 'class': 'td num' }, [ fmtBytes(d.tx) ]),
                E('td', { 'class': 'td num' }, [ String(d.domains || 0) ]),
                E('td', { 'class': 'td' }, [
                    E('button', { 'class': 'cbi-button cbi-button-action', 'click': ui.createHandlerFn(self, 'showDomains', d) }, [ '访问记录' ]),
                    ' ',
                    isMac(d.id) ? E('button', { 'class': 'cbi-button', 'click': ui.createHandlerFn(self, 'rename', d) }, [ '改名' ]) : ''
                ])
            ]);
        });

        dom.content(document.getElementById('zzm-table'), E('table', { 'class': 'table cbi-section-table' }, [
            E('tr', { 'class': 'tr table-titles' }, [
                E('th', { 'class': 'th' }, [ '设备' ]),
                E('th', { 'class': 'th' }, [ 'IP' ]),
                E('th', { 'class': 'th' }, [ '实时速率' ]),
                E('th', { 'class': 'th num' }, [ '下载' ]),
                E('th', { 'class': 'th num' }, [ '上传' ]),
                E('th', { 'class': 'th num' }, [ '访问域名数' ]),
                E('th', { 'class': 'th' }, [ '' ])
            ])
        ].concat(rows)));
    },

    rename: function(d) {
        var self = this;
        var input = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'value': d.name || '', 'placeholder': '留空 = 恢复为 DHCP 主机名', 'maxlength': 32 });
        ui.showModal('设备改名：' + d.id, [
            E('p', {}, [ input ]),
            E('p', { 'style': 'font-size:12px;opacity:.7' }, [ '不能包含空格（会替换为 _）、引号和等号；最多约 10 个汉字。' ]),
            E('div', { 'class': 'right' }, [
                E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, [ '取消' ]), ' ',
                E('button', { 'class': 'cbi-button cbi-button-positive', 'click': function() {
                    return callAlias(d.id, input.value.trim()).then(function() {
                        ui.hideModal();
                        return self.refresh();
                    });
                } }, [ '保存' ])
            ])
        ]);
        input.focus();
    },

    showDomains: function(d) {
        var day = this.day;
        var list = E('div', { 'class': 'zzm-dlg-list' }, [ E('em', {}, [ '加载中…' ]) ]);
        var search = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'placeholder': '搜索域名' });
        var merge = E('input', { 'type': 'checkbox', 'checked': true });
        var data = [];

        var render = function() {
            var q = search.value.trim().toLowerCase(), rows = data.slice().sort(function(a, b) { return b[1] - a[1]; });
            if (merge.checked) {
                var g = {};
                data.forEach(function(x) {
                    var b = baseDomain(x[0]);
                    if (!g[b]) g[b] = [ b, 0, '', 0 ];
                    g[b][1] += x[1];
                    if (x[2] > g[b][2]) g[b][2] = x[2];
                    g[b][3]++;
                });
                rows = Object.keys(g).map(function(k) { return g[k]; }).sort(function(a, b) { return b[1] - a[1]; });
            }
            if (q) rows = rows.filter(function(x) { return x[0].indexOf(q) >= 0; });
            var shown = rows.slice(0, 500);
            dom.content(list, rows.length ? [
                E('table', { 'class': 'table' }, [
                    E('tr', { 'class': 'tr table-titles' }, [
                        E('th', { 'class': 'th' }, [ merge.checked ? '主域名（子域名数）' : '域名' ]),
                        E('th', { 'class': 'th num' }, [ '查询次数' ]),
                        E('th', { 'class': 'th num' }, [ '最近' ])
                    ])
                ].concat(shown.map(function(x) {
                    return E('tr', { 'class': 'tr' }, [
                        E('td', { 'class': 'td' }, [ x[0] + (merge.checked && x[3] > 1 ? '（' + x[3] + '）' : '') ]),
                        E('td', { 'class': 'td num' }, [ String(x[1]) ]),
                        E('td', { 'class': 'td num' }, [ x[2] || '' ])
                    ]);
                }))),
                rows.length > shown.length ? E('p', {}, [ '仅显示前 500 条，共 ' + rows.length + ' 条，可用搜索缩小范围' ]) : ''
            ] : E('em', {}, [ '没有记录' ]));
        };

        search.addEventListener('input', render);
        merge.addEventListener('change', render);

        ui.showModal('访问记录：' + (d.name || d.id) + ' · ' + fmtDay(day, this.today), [
            E('div', { 'class': 'zzm-dlg-ctl' }, [
                search,
                E('label', {}, [ merge, ' 按主域名合并' ])
            ]),
            list,
            E('p', { 'style': 'font-size:12px;opacity:.7' }, [
                '统计的是设备向路由器查询域名的次数（打开网页 / App 后台都会产生），不是访问次数；HTTPS 下看不到具体网址。'
            ]),
            E('div', { 'class': 'right' }, [ E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, [ '关闭' ]) ])
        ], 'cbi-modal');

        return callDomains(d.id, day).then(function(r) {
            data = (r && r.domains) || [];
            render();
        }).catch(function(e) {
            dom.content(list, E('em', {}, [ '读取失败：' + (e && e.message ? e.message : e) ]));
        });
    },

    render: function(data) {
        var self = this, days = (data[0] && data[0].days) || [];
        this.today = (data[0] && data[0].today) || '';
        this.day = this.today || days[0] || '';
        if (days.indexOf(this.day) < 0 && this.day) days.unshift(this.day);

        var sel = E('select', { 'class': 'cbi-input-select', 'change': function(ev) {
            self.day = ev.target.value;
            self.prev = {}; self.rates = {};
            dom.content(document.getElementById('zzm-table'), E('div', { 'class': 'zzm-empty' }, [ '加载中…' ]));
            self.refresh();
        } }, days.map(function(d) { return E('option', { 'value': d }, [ fmtDay(d, self.today) ]); }));

        var m = new form.Map('zzucampusnetagent', null, null);
        var s = m.section(form.NamedSection, 'netmon', 'netmon', '设置');
        s.addremove = false;
        var o;

        o = s.option(form.Flag, 'enabled', '启用',
            '统计各设备的上传 / 下载流量，并记录各设备查询过的域名。只记录在路由器上，不上传任何地方。');
        o.default = '0';
        o.rmempty = false;

        o = s.option(widgets.NetworkSelect, 'iface', '监控的局域网', '可多选（例如 lan 与 lancm）');
        o.multiple = true;
        o.nocreate = true;
        o.default = 'lan';

        o = s.option(form.Flag, 'dns', '记录访问的域名',
            '开启 dnsmasq 查询日志（写在内存里，每 5 分钟汇总后清空）。关闭后只统计流量。');
        o.default = '1';
        o.rmempty = false;

        o = s.option(form.Value, 'retention', '保留天数', '历史数据每小时压缩保存到闪存，超过天数自动删除');
        o.datatype = 'range(1,365)';
        o.placeholder = '30';
        o.default = '30';

        return m.render().then(function(mapEl) {
            poll.add(function() {
                return self.day === self.today ? self.refresh() : Promise.resolve();
            }, 5);

            var page = E('div', { 'class': 'zzm' }, [
                E('style', { 'type': 'text/css' }, STYLE),
                E('h2', {}, [ '设备监控' ]),
                E('div', { 'class': 'zzm-note' }, [
                    '流量在局域网网桥上按设备计数（开启流量卸载也准确）；访问记录来自 DNS 查询，只能看到域名。',
                    '设备若自行使用加密 DNS（如浏览器「安全 DNS」），其访问记录会缺失。监控他人设备前请告知使用者。'
                ]),
                E('div', { 'class': 'cbi-section' }, [
                    E('div', { 'class': 'zzm-bar' }, [ E('span', {}, [ '日期 ' ]), sel, E('span', { 'id': 'zzm-sum', 'class': 'zzm-sum' }) ]),
                    E('div', { 'id': 'zzm-table' }, [ E('div', { 'class': 'zzm-empty' }, [ '加载中…' ]) ])
                ]),
                mapEl
            ]);
            self.refresh();
            return page;
        });
    }
});
