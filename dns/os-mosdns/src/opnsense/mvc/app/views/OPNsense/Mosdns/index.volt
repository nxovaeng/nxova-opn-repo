{#
 # Copyright (C) 2026 nxovaeng
 # All rights reserved.
 #}

<script>
    $(document).ready(function() {
        var data_get_map = {
            'frm_GeneralSettings': "/api/mosdns/settings/get",
            'frm_ForwardSettings': "/api/mosdns/settings/get",
            'frm_PfaliasSettings': "/api/mosdns/settings/get"
        };
        mapDataToFormUI(data_get_map).done(function(data) {
            $('.selectpicker').selectpicker('refresh');
        });

        function saveSection(formid) {
            saveFormToEndpoint(url="/api/mosdns/settings/set", formid=formid,
                callback_ok=function() {
                    $("#responseMsg").removeClass("hidden")
                        .removeClass("alert-danger alert-info").addClass("alert-success")
                        .html("{{ lang._('Settings saved. Press Apply to activate.') }}");
                },
                callback_fail=function() {
                    $("#responseMsg").removeClass("hidden")
                        .removeClass("alert-success alert-info").addClass("alert-danger")
                        .html("{{ lang._('Failed to save settings.') }}");
                }
            );
        }

        $("#saveGeneralAct").click(function() { saveSection('frm_GeneralSettings'); });
        $("#saveForwardAct").click(function() { saveSection('frm_ForwardSettings'); });
        $("#savePfaliasAct").click(function() { saveSection('frm_PfaliasSettings'); });

        $("#reconfigureAct").click(function() {
            $("#reconfigureAct_progress").addClass("fa fa-spinner fa-pulse");
            ajaxCall(url="/api/mosdns/service/reconfigure", sendData={}, callback=function(data, status) {
                $("#reconfigureAct_progress").removeClass("fa fa-spinner fa-pulse");
                var msg, cls;
                if (data['status'] == 'ok') {
                    msg = "{{ lang._('Configuration applied.') }}";
                    cls = "alert-success";
                } else {
                    msg = (data['status_msg'] || "{{ lang._('Apply failed.') }}");
                    cls = "alert-danger";
                }
                $("#responseMsg").removeClass("hidden alert-success alert-danger alert-info").addClass(cls).html(msg);
                refreshStatus();
            });
        });

        function refreshStatus() {
            ajaxCall(url="/api/mosdns/service/status", sendData={}, callback=function(data, status) {
                $("#serviceStatus").text("{{ lang._('Status') }}: " + (data['status'] || status));
            });
        }
        refreshStatus();
    });
</script>

<div id="svc-btns" class="btn-group pull-right" role="group" aria-label="mosdns" style="display:none;">
    <button id="svc-start" type="button" class="btn btn-default btn-xs" title="{{ lang._('启动') }}">
        <i class="fa fa-play fa-fw"></i>
    </button>
    <button id="svc-restart" type="button" class="btn btn-default btn-xs" title="{{ lang._('重启') }}">
        <i class="fa fa-refresh fa-fw"></i>
    </button>
    <button id="svc-stop" type="button" class="btn btn-default btn-xs" title="{{ lang._('停止') }}">
        <i class="fa fa-square fa-fw"></i>
    </button>
</div>
<script>
    $(document).ready(function() {
        // 移到页面标题同一行（OPNsense 内置风格）
        var $h1 = $('h1').first();
        if ($h1.length) { $('#svc-btns').show().detach().appendTo($h1); }
        else { $('#svc-btns').show(); }
        function refreshSvc() {
            ajaxCall(url="/api/mosdns/service/status", sendData={}, callback=function(data, status) {
                var running = data['status'] == 'running';
                $("#svc-start").prop("disabled", running).toggleClass("btn-success", !running).toggleClass("btn-default", running);
                $("#svc-stop").prop("disabled", !running);
                $("#svc-restart").prop("disabled", !running);
            });
        }
        function svcAct(act) {
            ajaxCall(url="/api/mosdns/service/" + act, sendData={}, callback=function(data, status) {
                setTimeout(refreshSvc, 1500);
            });
        }
        $("#svc-start").click(function() { svcAct('start'); });
        $("#svc-restart").click(function() { svcAct('restart'); });
        $("#svc-stop").click(function() { svcAct('stop'); });
        refreshSvc();
    });
</script>

<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
    <li class="active"><a data-toggle="tab" href="#general">通用</a></li>
    <li><a data-toggle="tab" href="#forward">转发</a></li>
    <li><a data-toggle="tab" href="#pfalias">PF 表同步</a></li>
</ul>
<div class="tab-content content-box tab-content">
    <div id="general" class="tab-pane fade in active">
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
                    <td><button class="btn btn-primary" id="saveGeneralAct" type="button"><b>{{ lang._('Save') }}</b></button></td>
                    <td></td>
                </tr>
            </tbody>
        </table>
    </div>
    <div id="forward" class="tab-pane fade">
        {{ partial("layout_partials/base_form",['fields':forwardForm,'id':'frm_ForwardSettings']) }}
        <table style="table-layout: fixed; width: 100%;">
            <colgroup>
                <col style="width: 25%;"/>
                <col style="width: 40%;"/>
                <col style="width: 35%;"/>
            </colgroup>
            <tbody>
                <tr>
                    <td></td>
                    <td><button class="btn btn-primary" id="saveForwardAct" type="button"><b>{{ lang._('Save') }}</b></button></td>
                    <td></td>
                </tr>
            </tbody>
        </table>
    </div>
    <div id="pfalias" class="tab-pane fade">
        {{ partial("layout_partials/base_form",['fields':pfaliasForm,'id':'frm_PfaliasSettings']) }}
        <table style="table-layout: fixed; width: 100%;">
            <colgroup>
                <col style="width: 25%;"/>
                <col style="width: 40%;"/>
                <col style="width: 35%;"/>
            </colgroup>
            <tbody>
                <tr>
                    <td></td>
                    <td><button class="btn btn-primary" id="savePfaliasAct" type="button"><b>{{ lang._('Save') }}</b></button></td>
                    <td></td>
                </tr>
            </tbody>
        </table>
    </div>
</div>

<div class="content-box" style="margin-top: 20px;">
    <div class="col-md-12">
        <button class="btn btn-primary" id="reconfigureAct" type="button">
            <b>{{ lang._('Apply') }}</b> <i id="reconfigureAct_progress"></i>
        </button>
        <span id="serviceStatus" class="text-muted" style="margin-left: 10px;"></span>
    </div>
    <div class="col-md-12" style="margin-top: 10px;">
        <div id="responseMsg" class="alert hidden" role="alert"></div>
    </div>
</div>
