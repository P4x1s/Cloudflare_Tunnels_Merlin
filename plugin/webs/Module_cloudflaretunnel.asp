<!--
=============================================================================
 ASUSGO / koolshare softcenter Web module
 Module: cloudflaretunnel (Cloudflare Tunnel)
 Path on router: /koolshare/webs/Module_cloudflaretunnel.asp
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
/* 读取 dbus 中本插件配置项 */
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
</style>

<div class="row">
    <div class="col-lg-12">
        <div class="ct-card">
            <h3>Cloudflare Tunnel 设置</h3>
            <p style="color:#888;">通过 Token 远程管理隧道，将内网服务安全暴露到公网（无需公网 IP）。</p>

            <div class="ct-row">
                <span class="ct-label">插件开关：</span>
                <input type="checkbox" id="ct_enable" /> 启用（开机自启）
            </div>
            <div class="ct-row">
                <span class="ct-label">隧道模式：</span>
                <select id="ct_mode">
                    <option value="remote">远程管理（Token，推荐）</option>
                    <option value="local">本地管理（config.yml）</option>
                </select>
            </div>
            <div class="ct-row" id="ct_token_row">
                <span class="ct-label">隧道 Token：</span>
                <input type="password" id="ct_token" class="ct-input" placeholder="Zero Trust → Networks → Tunnels → Configure 复制的 Token" />
            </div>
            <div class="ct-row" id="ct_name_row">
                <span class="ct-label">隧道名称：</span>
                <input type="text" id="ct_name" class="ct-input" placeholder="本地模式下的 tunnel name / UUID" />
            </div>
            <div class="ct-row">
                <span class="ct-label">日志级别：</span>
                <select id="ct_loglevel">
                    <option value="debug">debug</option>
                    <option value="info">info</option>
                    <option value="warn">warn</option>
                    <option value="error">error</option>
                </select>
            </div>
            <div class="ct-row">
                <span class="ct-label">附加参数：</span>
                <input type="text" id="ct_extra" class="ct-input" placeholder="例如 --edge-ip-version 4" />
            </div>

            <div class="ct-row">
                <button class="ct-btn btn btn-primary" id="ct_save">保存</button>
                <button class="ct-btn btn btn-success" id="ct_start">启动</button>
                <button class="ct-btn btn btn-warning" id="ct_stop">停止</button>
                <button class="ct-btn btn btn-default" id="ct_restart">重启</button>
            </div>
        </div>

        <div class="ct-card">
            <h3>运行状态</h3>
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

    // 初始化表单值（由后端 dbus 注入）
    function initForm(){
        $('ct_enable').checked   = ('<%= dbus get cloudflaretunnel_enable %>' === '1');
        $('ct_mode').value       = '<%= dbus get cloudflaretunnel_mode %>' || 'remote';
        $('ct_token').value      = '<%= dbus get cloudflaretunnel_token %>' || '';
        $('ct_name').value       = '<%= dbus get cloudflaretunnel_name %>' || '';
        $('ct_loglevel').value   = '<%= dbus get cloudflaretunnel_loglevel %>' || 'info';
        $('ct_extra').value      = '<%= dbus get cloudflaretunnel_extra %>' || '';
        toggleModeRows();
    }

    function toggleModeRows(){
        var remote = $('ct_mode').value === 'remote';
        $('ct_token_row').style.display = remote ? '' : 'none';
        $('ct_name_row').style.display  = remote ? 'none' : '';
    }

    // 通过 softcenter 的 dbus ajax 接口保存配置
    function saveCfg(){
        var params = {
            cloudflaretunnel_enable:    $('ct_enable').checked ? '1' : '0',
            cloudflaretunnel_mode:      $('ct_mode').value,
            cloudflaretunnel_token:     $('ct_token').value,
            cloudflaretunnel_name:      $('ct_name').value,
            cloudflaretunnel_loglevel:  $('ct_loglevel').value,
            cloudflaretunnel_extra:     $('ct_extra').value
        };
        var qs = [];
        for (var k in params) qs.push(k + '=' + encodeURIComponent(params[k]));
        return $.ajax({
            url: '/cgi-bin/dbus_set.cgi?' + qs.join('&'),
            type: 'GET', dataType: 'text'
        });
    }

    function runCmd(cmd){
        return $.ajax({
            url: '/cgi-bin/softcenter_cmd.cgi?cmd=' + encodeURIComponent(SCRIPT + ' ' + cmd),
            type: 'GET', dataType: 'text', timeout: 15000
        });
    }

    function refreshStatus(){
        $.ajax({
            url: '/cgi-bin/softcenter_cmd.cgi?cmd=' + encodeURIComponent(SCRIPT + ' status'),
            type: 'GET', dataType: 'text', timeout: 15000,
            success: function(data){ $('ct_status').innerText = data; },
            error: function(){ $('ct_status').innerText = '状态获取失败'; }
        });
    }

    $('ct_mode').addEventListener('change', toggleModeRows);
    $('ct_save').addEventListener('click', function(){
        saveCfg().done(function(){ alert('保存成功'); });
    });
    $('ct_start').addEventListener('click', function(){ runCmd('start').done(refreshStatus); });
    $('ct_stop').addEventListener('click',  function(){ runCmd('stop').done(refreshStatus); });
    $('ct_restart').addEventListener('click',function(){ runCmd('restart').done(refreshStatus); });
    $('ct_refresh').addEventListener('click',refreshStatus);
    $('ct_logbtn').addEventListener('click',function(){
        $('ct_log').style.display = 'block';
        $.ajax({
            url: '/cgi-bin/softcenter_cmd.cgi?cmd=' + encodeURIComponent(SCRIPT + ' log 100'),
            type: 'GET', dataType: 'text',
            success: function(data){ $('ct_log').innerText = data; }
        });
    });

    initForm();
    refreshStatus();
})();
</script>
