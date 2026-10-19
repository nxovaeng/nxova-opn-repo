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

<div class="row" style="margin-bottom: 10px;">
    <div class="col-md-12">
        <div class="pull-right">
            <span id="svc-mosdns" style="margin-right: 15px;">
                <i id="svc-mosdns-icon" class="fa fa-circle text-muted"></i>
                <strong>mosdns</strong>
                <button id="svc-mosdns-restart" class="btn btn-default btn-xs" type="button" title="{{ lang._('Restart') }}">
                    <i class="fa fa-refresh"></i>
                </button>
                <button id="svc-mosdns-toggle" class="btn btn-default btn-xs" type="button" title="{{ lang._('Start/Stop') }}">
                    <i class="fa fa-power-off"></i>
                </button>
            </span>
            <span id="svc-pfaliasd">
                <i id="svc-pfaliasd-icon" class="fa fa-circle text-muted"></i>
                <strong>pf-aliasd</strong>
                <button id="svc-pfaliasd-restart" class="btn btn-default btn-xs" type="button" title="{{ lang._('Restart') }}">
                    <i class="fa fa-refresh"></i>
                </button>
                <button id="svc-pfaliasd-toggle" class="btn btn-default btn-xs" type="button" title="{{ lang._('Start/Stop') }}">
                    <i class="fa fa-power-off"></i>
                </button>
            </span>
        </div>
        <div class="clearfix"></div>
    </div>
</div>
<script>
    $(document).ready(function() {
        function setSvcIcon(id, running) {
            $("#" + id).removeClass("text-muted text-success text-danger")
                .addClass(running ? "text-success" : "text-danger");
        }
        function refreshSvc() {
            ajaxCall(url="/api/mosdns/service/status", sendData={}, callback=function(data, status) {
                setSvcIcon("svc-mosdns-icon", data['status'] == 'running');
            });
            ajaxCall(url="/api/mosdns/service/pfaliasdStatus", sendData={}, callback=function(data, status) {
                setSvcIcon("svc-pfaliasd-icon", data['status'] == 'running');
            });
        }
        function svcAct(svc, act) {
            var url = svc == 'mosdns' ? "/api/mosdns/service/" + act : "/api/mosdns/service/pfaliasd" + act.charAt(0).toUpperCase() + act.slice(1);
            ajaxCall(url=url, sendData={}, callback=function(data, status) {
                setTimeout(refreshSvc, 1000);
            });
        }
        $("#svc-mosdns-restart").click(function() { svcAct('mosdns', 'restart'); });
        $("#svc-pfaliasd-restart").click(function() { svcAct('pfaliasd', 'restart'); });
        $("#svc-mosdns-toggle").click(function() {
            var running = $("#svc-mosdns-icon").hasClass("text-success");
            svcAct('mosdns', running ? 'stop' : 'start');
        });
        $("#svc-pfaliasd-toggle").click(function() {
            var running = $("#svc-pfaliasd-icon").hasClass("text-success");
            svcAct('pfaliasd', running ? 'stop' : 'start');
        });
        refreshSvc();
    });
</script>

<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
    <li class="active"><a data-toggle="tab" href="#general">{{ lang._('General') }}</a></li>
    <li><a data-toggle="tab" href="#forward">{{ lang._('Forwarding') }}</a></li>
    <li><a data-toggle="tab" href="#pfalias">{{ lang._('PF table sync') }}</a></li>
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
