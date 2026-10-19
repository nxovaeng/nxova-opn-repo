{#
 # Copyright (C) 2026 nxovaeng
 # All rights reserved.
 #}

<script>
    $(document).ready(function() {
        var data_get_map = {
            'frm_PfaliasdSettings': "/api/mosdns/settings/get"
        };
        mapDataToFormUI(data_get_map).done(function(data) {
            $('.selectpicker').selectpicker('refresh');
        });

        $("#savePfaliasdAct").click(function() {
            saveFormToEndpoint(url="/api/mosdns/settings/set", formid='frm_PfaliasdSettings',
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
        });

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
                setTimeout(refreshSvc, 1000);
            });
        });

        function setSvcIcon(id, running) {
            $("#" + id).removeClass("text-muted text-success text-danger")
                .addClass(running ? "text-success" : "text-danger");
        }
        function refreshSvc() {
            ajaxCall(url="/api/mosdns/service/pfaliasdStatus", sendData={}, callback=function(data, status) {
                setSvcIcon("svc-pfaliasd-icon", data['status'] == 'running');
            });
        }
        $("#svc-pfaliasd-restart").click(function() {
            ajaxCall(url="/api/mosdns/service/pfaliasdRestart", sendData={}, callback=function(data, status) {
                setTimeout(refreshSvc, 1000);
            });
        });
        $("#svc-pfaliasd-toggle").click(function() {
            var running = $("#svc-pfaliasd-icon").hasClass("text-success");
            var act = running ? 'pfaliasdStop' : 'pfaliasdStart';
            ajaxCall(url="/api/mosdns/service/" + act, sendData={}, callback=function(data, status) {
                setTimeout(refreshSvc, 1000);
            });
        });
        refreshSvc();
    });
</script>

<div class="row" style="margin-bottom: 10px;">
    <div class="col-md-12">
        <div class="pull-right">
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

<div class="content-box">
    {{ partial("layout_partials/base_form",['fields':pfaliasdForm,'id':'frm_PfaliasdSettings']) }}
    <table style="table-layout: fixed; width: 100%;">
        <colgroup>
            <col style="width: 25%;"/>
            <col style="width: 40%;"/>
            <col style="width: 35%;"/>
        </colgroup>
        <tbody>
            <tr>
                <td></td>
                <td><button class="btn btn-primary" id="savePfaliasdAct" type="button"><b>{{ lang._('Save') }}</b></button></td>
                <td></td>
            </tr>
        </tbody>
    </table>
</div>

<div class="col-md-12" style="margin-top: 20px;">
    <div class="content-box">
        <button class="btn btn-primary" id="reconfigureAct" type="button">
            <b>{{ lang._('Apply') }}</b> <i id="reconfigureAct_progress"></i>
        </button>
        <span id="responseMsg" class="hidden alert" style="margin-left: 10px; padding: 6px 12px;"></span>
    </div>
</div>
