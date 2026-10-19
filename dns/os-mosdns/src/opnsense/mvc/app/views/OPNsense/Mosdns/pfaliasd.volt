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

        function refreshSvc() {
            ajaxCall(url="/api/mosdns/service/pfaliasdStatus", sendData={}, callback=function(data, status) {
                var running = data['status'] == 'running';
                $("#svc-start").prop("disabled", running).toggleClass("btn-success", !running).toggleClass("btn-default", running);
                $("#svc-stop").prop("disabled", !running);
                $("#svc-restart").prop("disabled", !running);
            });
        }
        $("#svc-start").click(function() {
            ajaxCall(url="/api/mosdns/service/pfaliasdStart", sendData={}, callback=function(data, status) {
                setTimeout(refreshSvc, 1500);
            });
        });
        $("#svc-restart").click(function() {
            ajaxCall(url="/api/mosdns/service/pfaliasdRestart", sendData={}, callback=function(data, status) {
                setTimeout(refreshSvc, 1500);
            });
        });
        $("#svc-stop").click(function() {
            ajaxCall(url="/api/mosdns/service/pfaliasdStop", sendData={}, callback=function(data, status) {
                setTimeout(refreshSvc, 1500);
            });
        });
        refreshSvc();
    });
</script>

<div class="row" style="margin-bottom: 10px;">
    <div class="col-md-12">
        <div class="pull-right">
            <div class="btn-group" role="group" aria-label="pf-aliasd">
                <button id="svc-start" type="button" class="btn btn-default btn-xs" title="{{ lang._('Start') }}">
                    <i class="fa fa-play fa-fw"></i>
                </button>
                <button id="svc-restart" type="button" class="btn btn-default btn-xs" title="{{ lang._('Restart') }}">
                    <i class="fa fa-refresh fa-fw"></i>
                </button>
                <button id="svc-stop" type="button" class="btn btn-default btn-xs" title="{{ lang._('Stop') }}">
                    <i class="fa fa-square fa-fw"></i>
                </button>
            </div>
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
