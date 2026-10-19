{#
 # Copyright (C) 2026 nxovaeng
 # All rights reserved.
 #}

<script>
    $(document).ready(function() {
        var data_get_map = {
            'frm_TunnelSettings': "/api/tun2socks/settings/get",
            'frm_Socks5Settings': "/api/tun2socks/settings/get",
            'frm_MiscSettings': "/api/tun2socks/settings/get"
        };
        mapDataToFormUI(data_get_map).done(function(data) {
            $('.selectpicker').selectpicker('refresh');
        });

        function saveSection(formid) {
            saveFormToEndpoint(url="/api/tun2socks/settings/set", formid=formid,
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

        $("#saveTunnelAct").click(function() { saveSection('frm_TunnelSettings'); });
        $("#saveSocks5Act").click(function() { saveSection('frm_Socks5Settings'); });
        $("#saveMiscAct").click(function() { saveSection('frm_MiscSettings'); });

        $("#reconfigureAct").click(function() {
            $("#reconfigureAct_progress").addClass("fa fa-spinner fa-pulse");
            ajaxCall(url="/api/tun2socks/service/reconfigure", sendData={}, callback=function(data, status) {
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
            ajaxCall(url="/api/tun2socks/service/status", sendData={}, callback=function(data, status) {
                $("#serviceStatus").text("{{ lang._('Status') }}: " + (data['status'] || status));
            });
        }

        refreshStatus();
    });
</script>

<div class="row" style="margin-bottom: 10px;">
    <div class="col-md-12">
        <div class="pull-right">
            <div class="btn-group" role="group" aria-label="tun2socks">
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
        </div>
        <div class="clearfix"></div>
    </div>
</div>
<script>
    $(document).ready(function() {
        function refreshSvcStatus() {
            ajaxCall(url="/api/tun2socks/service/status", sendData={}, callback=function(data, status) {
                var running = data['status'] == 'running';
                $("#svc-start").prop("disabled", running).toggleClass("btn-success", !running).toggleClass("btn-default", running);
                $("#svc-stop").prop("disabled", !running);
                $("#svc-restart").prop("disabled", !running);
            });
        }
        $("#svc-start").click(function() {
            ajaxCall(url="/api/tun2socks/service/start", sendData={}, callback=function(data, status) {
                setTimeout(refreshSvcStatus, 1500);
            });
        });
        $("#svc-restart").click(function() {
            ajaxCall(url="/api/tun2socks/service/restart", sendData={}, callback=function(data, status) {
                setTimeout(refreshSvcStatus, 1500);
            });
        });
        $("#svc-stop").click(function() {
            ajaxCall(url="/api/tun2socks/service/stop", sendData={}, callback=function(data, status) {
                setTimeout(refreshSvcStatus, 1500);
            });
        });
        refreshSvcStatus();
    });
</script>

<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
    <li class="active"><a data-toggle="tab" href="#tunnel">隧道</a></li>
    <li><a data-toggle="tab" href="#socks5">{{ lang._('SOCKS5') }}</a></li>
    <li><a data-toggle="tab" href="#misc">其他</a></li>
</ul>
<div class="tab-content content-box tab-content">
    <div id="tunnel" class="tab-pane fade in active">
        {{ partial("layout_partials/base_form",['fields':tunnelForm,'id':'frm_TunnelSettings']) }}
        <table style="table-layout: fixed; width: 100%;">
            <colgroup>
                <col style="width: 25%;"/>
                <col style="width: 40%;"/>
                <col style="width: 35%;"/>
            </colgroup>
            <tbody>
                <tr>
                    <td></td>
                    <td><button class="btn btn-primary" id="saveTunnelAct" type="button"><b>{{ lang._('Save') }}</b></button></td>
                    <td></td>
                </tr>
            </tbody>
        </table>
    </div>
    <div id="socks5" class="tab-pane fade">
        {{ partial("layout_partials/base_form",['fields':socks5Form,'id':'frm_Socks5Settings']) }}
        <table style="table-layout: fixed; width: 100%;">
            <colgroup>
                <col style="width: 25%;"/>
                <col style="width: 40%;"/>
                <col style="width: 35%;"/>
            </colgroup>
            <tbody>
                <tr>
                    <td></td>
                    <td><button class="btn btn-primary" id="saveSocks5Act" type="button"><b>{{ lang._('Save') }}</b></button></td>
                    <td></td>
                </tr>
            </tbody>
        </table>
    </div>
    <div id="misc" class="tab-pane fade">
        {{ partial("layout_partials/base_form",['fields':miscForm,'id':'frm_MiscSettings']) }}
        <table style="table-layout: fixed; width: 100%;">
            <colgroup>
                <col style="width: 25%;"/>
                <col style="width: 40%;"/>
                <col style="width: 35%;"/>
            </colgroup>
            <tbody>
                <tr>
                    <td></td>
                    <td><button class="btn btn-primary" id="saveMiscAct" type="button"><b>{{ lang._('Save') }}</b></button></td>
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
