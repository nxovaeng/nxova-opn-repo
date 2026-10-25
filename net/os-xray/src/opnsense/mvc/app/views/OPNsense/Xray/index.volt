{#
 # Copyright (C) 2026 nxovaeng
 # All rights reserved.
 #}

<script>
    function escHtml(s) {
        return $('<div>').text(s == null ? '' : String(s)).html();
    }

    $(document).ready(function() {
        // ---- validation error banner (P0-2) ----
        function refreshValidationBanner() {
            ajaxCall(url="/api/xray/service/getValidationError", sendData={}, callback=function(data, status) {
                var err = (data['error'] || '').trim();
                if (err) {
                    $("#validationBanner").removeClass("hidden").text("上次配置生成失败（旧配置仍在运行）：" + err);
                } else {
                    $("#validationBanner").addClass("hidden").text("");
                }
            });
        }
        refreshValidationBanner();

        // ---- general settings ----
        mapDataToFormUI({'frm_GeneralSettings': "/api/xray/settings/get"}).done(function() {
            $('.selectpicker').selectpicker('refresh');
            // dns_servers one-per-line textarea (mirror pattern: the hidden
            // input still submits comma-separated, so model/generator unchanged)
            var $dnsInput = $('#frm_GeneralSettings input[name="xray.general.dns_servers"]');
            if ($dnsInput.length && $('#dnsServersArea').length === 0) {
                var $area = $('<textarea id="dnsServersArea" class="form-control" rows="3"></textarea>');
                $dnsInput.hide().after($area);
                $area.val($dnsInput.val().split(',').map(function(s) { return s.trim(); }).filter(Boolean).join('\n'));
                $area.on('input', function() {
                    $dnsInput.val($(this).val().split('\n').map(function(s) { return s.trim(); }).filter(Boolean).join(','));
                });
            }
        });
        $("#saveGeneralAct").click(function() {
            saveFormToEndpoint(url="/api/xray/settings/set", formid='frm_GeneralSettings',
                callback_ok=function() {
                    $("#responseMsg").removeClass("hidden alert-danger alert-info").addClass("alert-success")
                        .html("设置已保存，点底部「应用」生效。");
                });
        });

        // ---- grids ----
        $("#grid-inbounds").UIBootgrid({
            search: '/api/xray/settings/searchInbounds',
            get: '/api/xray/settings/getInbound/',
            set: '/api/xray/settings/setInbound/',
            add: '/api/xray/settings/addInbound/',
            del: '/api/xray/settings/delInbound/',
            toggle: '/api/xray/settings/toggleInbound/'
        });

        // ---- apply ----
        $("#reconfigureAct").click(function() {
            $("#reconfigureAct_progress").addClass("fa fa-spinner fa-pulse");
            ajaxCall(url="/api/xray/service/reconfigure", sendData={}, callback=function(data, status) {
                $("#reconfigureAct_progress").removeClass("fa fa-spinner fa-pulse");
                var msg = data['status'] == 'ok' ? "配置已应用。" : (data['status_msg'] || "应用失败。");
                var cls = data['status'] == 'ok' ? "alert-success" : "alert-danger";
                $("#responseMsg").removeClass("hidden alert-success alert-danger alert-info").addClass(cls).html(escHtml(msg));
                updateServiceControlUI('xray');
                refreshValidationBanner();
            });
        });

        // ---- preview / test ----
        $("#previewAct").click(function() {
            ajaxCall(url="/api/xray/service/preview", sendData={}, callback=function(data, status) {
                $("#configPreview").text(data['result'] == 'ok' ? JSON.stringify(data['config'], null, 2) : (data['error'] || '生成失败'));
            });
        });
        $("#testConfigAct").click(function() {
            ajaxCall(url="/api/xray/service/testConfig", sendData={}, callback=function(data, status) {
                var $m = $("#settingsMsg");
                if (data['result'] == 'ok') {
                    $m.removeClass("hidden alert-danger").addClass("alert-success").text("当前已生成的配置校验通过（xray -test）。");
                } else {
                    $m.removeClass("hidden alert-success").addClass("alert-danger").text("校验失败：" + (data['output'] || ''));
                }
            });
        });

        // ---- logs ----
        function refreshLog() {
            ajaxCall(url="/api/xray/service/log", sendData={lines: 100}, callback=function(data, status) {
                $("#xrayLog").text(data['log'] || '');
            });
        }
        $("#refreshLogAct").click(refreshLog);

        updateServiceControlUI('xray');
    });
</script>

<div id="validationBanner" class="alert alert-danger hidden" role="alert" style="white-space: pre-wrap;"></div>
<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
    <li class="active"><a data-toggle="tab" href="#inbounds">入站</a></li>
    <li><a data-toggle="tab" href="#settings">设置</a></li>
    <li><a data-toggle="tab" href="#logs">日志</a></li>
</ul>
<div class="tab-content content-box tab-content">
    <div id="inbounds" class="tab-pane fade in active">
        <p class="text-muted">内置固定入站：hev-socks-in（127.0.0.1:10808，给 tun2socks 用）、dns-in（127.0.0.1:10853）。下面可加自定义入站，如给局域网开一个带认证的 socks。</p>
        <table id="grid-inbounds" class="table table-condensed table-hover table-striped" data-editDialog="DialogInbound">
            <thead>
                <tr>
                    <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">ID</th>
                    <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">启用</th>
                    <th data-column-id="tag" data-type="string">标签</th>
                    <th data-column-id="protocol" data-type="string">协议</th>
                    <th data-column-id="listen" data-type="string">监听</th>
                    <th data-column-id="port" data-type="string">端口</th>
                    <th data-column-id="commands" data-width="7em" data-formatter="commands" data-sortable="false">操作</th>
                </tr>
            </thead>
            <tbody></tbody>
            <tfoot>
                <tr>
                    <td></td>
                    <td>
                        <button data-action="add" type="button" class="btn btn-xs btn-default"><span class="fa fa-plus"></span></button>
                        <button data-action="deleteSelected" type="button" class="btn btn-xs btn-default"><span class="fa fa-trash-o"></span></button>
                    </td>
                </tr>
            </tfoot>
        </table>
    </div>
    <div id="settings" class="tab-pane fade">
        {{ partial("layout_partials/base_form",['fields':generalForm,'id':'frm_GeneralSettings']) }}
        <table style="table-layout: fixed; width: 100%;">
            <colgroup>
                <col style="width: 25%;"/>
                <col style="width: 40%;"/>
                <col style="width: 35%;"/>
            </colgroup>
            <tbody>
                <tr>
                    <td></td>
                    <td style="padding-top: 10px;"><button class="btn btn-primary" id="saveGeneralAct" type="button"><b>保存</b></button></td>
                    <td></td>
                </tr>
            </tbody>
        </table>
        <hr/>
        <button class="btn btn-default" id="previewAct" type="button">预览生成的配置</button>
        <button class="btn btn-default" id="testConfigAct" type="button">校验当前配置</button>
        <div id="settingsMsg" class="alert hidden" role="alert" style="margin-top: 10px;"></div>
        <pre id="configPreview" style="margin-top:10px; max-height:400px; overflow:auto;"></pre>
    </div>
    <div id="logs" class="tab-pane fade">
        <button class="btn btn-default btn-sm" id="refreshLogAct" type="button">刷新</button>
        <pre id="xrayLog" style="margin-top:10px; max-height:500px; overflow:auto; background:#000; color:#0f0;"></pre>
    </div>
</div>

<div class="content-box" style="margin-top: 20px; padding: 15px 0;">
    <div class="col-md-12">
        <button class="btn btn-primary" id="reconfigureAct" type="button">
            <b>应用</b> <i id="reconfigureAct_progress"></i>
        </button>
    </div>
    <div class="col-md-12" style="margin-top: 10px;">
        <div id="responseMsg" class="alert hidden" role="alert"></div>
    </div>
</div>

{{ partial("layout_partials/base_dialog",['fields':inboundForm,'id':'DialogInbound','label':lang._('编辑入站')])}}
