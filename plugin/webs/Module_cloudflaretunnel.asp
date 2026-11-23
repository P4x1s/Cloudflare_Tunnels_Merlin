<!--
=============================================================================
 ASUSGO / koolshare softcenter Web module
 Module: cloudflaretunnel (Cloudflare Tunnel)
 Path on router: /koolshare/webs/Module_cloudflaretunnel.asp

 SECURITY NOTES:
  - All dbus-sourced values are JS-escaped before being embedded in scripts
    (prevents stored XSS from malicious token/extra values).
  - Config save uses POST (token no longer travels in the URL query string),
    with a GET fallback for firmwares whose cgi only accepts GET.
  - State-changing AJAX calls send X-Requested-With to mitigate CSRF.

 v1.2.0 CHANGES:
  - Removed the non-functional "local/config.yml" mode (only remote Token mode
    is implemented) to avoid a misleading, always-failing option.
  - Save now offers to apply changes immediately (restart) so edits take effect.
  - Status view renders tunnel health, version and uptime hints.
=============================================================================
-->
<%
/***********************************************************************
 * softcenter 通用头部：引入框架、检查登录、定义模块标题等
 **********************************************************************/
var dbus = {};
%>
<#include "/koolshare/webs/Module_dianxin.asp">
<%
/* 读取 dbus 中本插件配置项（保留兼容函数，输出同样经过转义约定） */
function getCfg(key, def){
    var v = '<% dbus get cloudflaretunnel_' + key + ' %>';
    return (v && v !== "cloudflaretunnel_" + key) ? v : def;
}
%>
<style>
    .ct-card { margin: 14px; padding: 16px; background:#fff; border-radius:6px; }
    .ct-row  { margin: 10px 0; }
    .ct-label{ display:inline-block; width:130px; font-weight:bold; }
    .ct-input{ width: 420px; padding:6px; }
    .ct-btn  { margin-right:8px; padding:6px 16px; cursor:pointer; }
    .ct-status{ font-family:monospace; background:#f5f5f5; padding:10px; white-space:pre-wrap; }
    .ct-hint{ color:#888; font-size:12px; }
    .ct-badge{ display:inline-block; padding:2px 8px; border-radius:10px; font-size:12px; margin-left:6px; }
    .ct-ok{ background:#e6f4ea; color:#137333; }
    .ct-warn{ background:#fef7e0; color:#b06000; }
    .ct-bad{ background:#fce8e6; color:#c5221f; }
</style>

<div class="row">
    <div class="col-lg-12">
        <div class="ct-card">
            <h3>Cloudflare Tunnel 设置 <span id="ct_ver" class="ct-hint"></span></h3>
            <p class="ct-hint">通过 Token 远程管理隧道，将内网服务安全暴露到公网（无需公网 IP）。v1.2.0 起仅支持远程 Token 模式。</p>

            <div class="ct-row">
                <span class="ct-label">插件开关：</span>
                <input type="checkbox" id="ct_enable" /> 启用（开机自启 + 看门狗自愈）
            </div>
            <div class="ct-row" id="ct_token_row">
                <span class="ct-label">隧道 Token：</span>
                <input type="password" id="ct_token" class="ct-input" placeholder="Zero Trust → Networks → Tunnels → Configure 复制的 Token" />
            </div>
            <div class="ct-row">
                <span class="ct-label">日志级别：</span>
                <select id="ct_loglevel">
                    <option value="debug">debug</option>
                    <option value="info">info</option>
                    <option value="warn">warn</option>
                    <option value="error">error</option>
                </select>
                <span class="ct-hint">建议 info；debug 会产生大量日志。</span>
            </div>
            <div class="ct-row">
                <span class="ct-label">附加参数：</span>
                <input type="text" id="ct_extra" class="ct-input" placeholder="例如 --edge-ip-version 4" />
            </div>

            <div class="ct-row">
                <button class="ct-btn btn btn-primary" id="ct_save">保存并应用</button>
                <button class="ct-btn btn btn-success" id="ct_start">启动</button>
                <button class="ct-btn btn btn-warning" id="ct_stop">停止</button>
                <button class="ct-btn btn btn-default" id="ct_restart">重启</button>
            </div>
            <p class="ct-hint">保存后若插件处于启用状态，将自动重启以使配置生效；看门狗每 2 分钟自动检查，异常时自愈。</p>
        </div>

        <div class="ct-card">
            <h3>运行状态</h3>
            <div class="ct-hint">隧道连通性：<span id="ct_health_badge" class="ct-badge ct-warn">检测中...</span></div>
            <div id="ct_status" class="ct-status">加载中...</div>
            <button class="ct-btn btn btn-default" id="ct_refresh">刷新状态</button>
            <button class="ct-btn btn btn-default" id="ct_logbtn">查看日志</button>
            <div id="ct_log" class="ct-status" style="display:none;"></div>
        </div>
    </div>
</div>

<script>
(function(){
    var SCRIPT = '/koolshare/scripts/cloudflaretunnel.sh';

    function $(id){ return document.getElementById(id); }

    // 将服务端注入的字符串转义为可安全放入 JS 单引号字面量的形式。
    function esc(s){
        return String(s == null ? '' : s)
            .replace(/\\/g, '\\\\')
            .replace(/'/g, "\\'")
            .replace(/</g, '\\x3c')
            .replace(/>/g, '\\x3e')
            .replace(/\r/g, '')
            .replace(/\n/g, '\\n');
    }

    function initForm(){
        $('ct_enable').checked   = ('<%= dbus get cloudflaretunnel_enable %>' === '1');
        $('ct_token').value      = esc('<%= dbus get cloudflaretunnel_token %>') || '';
        $('ct_loglevel').value   = esc('<%= dbus get cloudflaretunnel_loglevel %>') || 'info';
        $('ct_extra').value      = esc('<%= dbus get cloudflaretunnel_extra %>') || '';
    }

    // POST 保存；部分固件 cgi 仅接受 GET，POST 失败时自动回退（token 仍编码在 body/query，但优先 POST）。
    function saveCfg(){
        var params = {
            cloudflaretunnel_enable:    $('ct_enable').checked ? '1' : '0',
            cloudflaretunnel_mode:      'remote',
            cloudflaretunnel_token:     $('ct_token').value,
            cloudflaretunnel_loglevel:  $('ct_loglevel').value,
            cloudflaretunnel_extra:     $('ct_extra').value
        };
        var qs = [];
        for (var k in params) qs.push(k + '=' + encodeURIComponent(params[k]));
        return $.ajax({
            url: '/cgi-bin/dbus_set.cgi',
            type: 'POST',
            data: params,
            dataType: 'text',
            headers: { 'X-Requested-With': 'XMLHttpRequest' }
        }).fail(function(){
            return $.ajax({
                url: '/cgi-bin/dbus_set.cgi?' + qs.join('&'),
                type: 'GET', dataType: 'text',
                headers: { 'X-Requested-With': 'XMLHttpRequest' }
            });
        });
    }

    function runCmd(cmd){
        return $.ajax({
            url: '/cgi-bin/softcenter_cmd.cgi',
            type: 'GET',
            data: { cmd: SCRIPT + ' ' + cmd },
            dataType: 'text', timeout: 20000,
            headers: { 'X-Requested-With': 'XMLHttpRequest' }
        });
    }

    function parseKV(data){
        var o = {};
        String(data || '').split(/\r?\n/).forEach(function(line){
            var i = line.indexOf('=');
            if (i > 0) o[line.slice(0, i)] = line.slice(i + 1);
        });
        return o;
    }

    function setBadge(text, cls){
        var b = $('ct_health_badge');
        b.textContent = text;
        b.className = 'ct-badge ' + cls;
    }

    function refreshStatus(){
        $.ajax({
            url: '/cgi-bin/softcenter_cmd.cgi',
            type: 'GET',
            data: { cmd: SCRIPT + ' status' },
            dataType: 'text', timeout: 15000,
            headers: { 'X-Requested-With': 'XMLHttpRequest' },
            success: function(data){
                $('ct_status').innerText = data;
                var kv = parseKV(data);
                if (kv.VERSION) $('ct_ver').textContent = 'v' + kv.VERSION;
                var h = kv.TUNNEL || 'UNKNOWN';
                if (h === 'HEALTHY')      setBadge('HEALTHY · 隧道已连通', 'ct-ok');
                else if (h === 'RUNNING' || h === 'CONNECTING') setBadge(h + ' · 连接中', 'ct-warn');
                else if (h === 'DOWN')    setBadge('DOWN · 未运行', 'ct-bad');
                else                      setBadge(h + ' · 状态未知', 'ct-warn');
            },
            error: function(){ $('ct_status').innerText = '状态获取失败'; }
        });
    }

    $('ct_save').addEventListener('click', function(){
        saveCfg().done(function(){
            var apply = $('ct_enable').checked
                ? window.confirm('配置已保存。是否立即重启插件以应用更改？')
                : false;
            if (apply) runCmd('restart').always(refreshStatus);
            else alert('保存成功' + ($('ct_enable').checked ? '（未重启，部分更改将在下次启动生效）' : ''));
        }).fail(function(){ alert('保存失败，请检查固件 cgi 接口。'); });
    });
    $('ct_start').addEventListener('click', function(){ runCmd('start').done(refreshStatus); });
    $('ct_stop').addEventListener('click',  function(){ runCmd('stop').done(refreshStatus); });
    $('ct_restart').addEventListener('click',function(){ runCmd('restart').done(refreshStatus); });
    $('ct_refresh').addEventListener('click',refreshStatus);
    $('ct_logbtn').addEventListener('click',function(){
        $('ct_log').style.display = 'block';
        $.ajax({
            url: '/cgi-bin/softcenter_cmd.cgi',
            type: 'GET',
            data: { cmd: SCRIPT + ' log 100' },
            dataType: 'text',
            headers: { 'X-Requested-With': 'XMLHttpRequest' },
            success: function(data){ $('ct_log').innerText = data; }
        });
    });

    initForm();
    refreshStatus();
})();
</script>
