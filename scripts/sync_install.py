# 用 root/ 与 htdocs/ 下的源文件重新生成 install.sh 中的 heredoc 段
# 改了 root/ 或 htdocs/ 下的文件后运行，与源文件一起提交：
#   python scripts/sync_install.py write        重新生成 install.sh
#   python scripts/sync_install.py check-head   对比 install.sh 与 HEAD 中的源文件
import os, re, subprocess, sys
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
MAP = {
    'ZZU_EOF_JS':    'htdocs/luci-static/resources/view/zzucampusnetagent/status.js',
    'ZZU_EOF_BIN':   'root/usr/sbin/zzucampusnetagent',
    'ZZU_EOF_RPCD':  'root/usr/libexec/rpcd/luci.zzucampusnetagent',
    'ZZU_EOF_INITD': 'root/etc/init.d/zzucampusnetagent',
    'ZZU_EOF_MENU':  'root/usr/share/luci/menu.d/luci-app-zzu-campusnet-agent.json',
    'ZZU_EOF_ACL':   'root/usr/share/rpcd/acl.d/luci-app-zzu-campusnet-agent.json',
    'ZZU_EOF_CFG':   'root/etc/config/zzucampusnetagent',
    'ZZU_EOF_JS_NETMON':      'htdocs/luci-static/resources/view/zzucampusnetagent/netmon.js',
    'ZZU_EOF_NETMON':         'root/usr/sbin/zzunetmon',
    'ZZU_EOF_NETMON_INITD':   'root/etc/init.d/zzunetmon',
    'ZZU_EOF_NETMON_HOTPLUG': 'root/etc/hotplug.d/iface/90-zzunetmon',
}
mode = sys.argv[1]
src = open('install.sh', encoding='utf-8', newline='').read()
def section(tag):
    m = re.search(r"<<'%s'\n(.*?)\n%s\n" % (tag, tag), src, re.S)
    assert m, tag
    return m
for tag, path in MAP.items():
    m = section(tag)
    if mode == 'check-head':
        head = subprocess.run(['git', 'show', 'HEAD:' + path], capture_output=True, encoding='utf-8').stdout.rstrip('\n')
        print(tag, 'same' if head == m.group(1) else 'DIFF')
    else:
        new = open(path, encoding='utf-8', newline='').read().replace('\r\n', '\n').rstrip('\n')
        src = src[:m.start(1)] + new + src[m.end(1):]
if mode == 'write':
    open('install.sh', 'w', encoding='utf-8', newline='\n').write(src)
    print('written')
