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

        // pf-aliasd is a companion daemon inside the mosdns module (it has no
        // own /api/<module>/service/* endpoints), so render core-style controls
        // into the standard #service_status_container from its custom endpoints.
        function refreshSvc() {
            ajaxCall(url="/api/mosdns/service/pfaliasdStatus", sendData={}, callback=function(data, status) {
                var running = data['status'] == 'running';
                var html = '<span class="label label-opnsense label-opnsense-sm ' + (running ? 'label-success' : 'label-danger') + '">'
                         + '<i class="fa fa-' + (running ? 'play' : 'stop') + ' fa-fw"></i></span> ';
                if (running) {
                    html += '<span id="pfSvcRestart" class="btn btn-sm btn-default" title="{{ lang._('Restart') }}"><i class="fa fa-repeat fa-fw"></i></span>';
                    html += '<span id="pfSvcStop" class="btn btn-sm btn-default" title="{{ lang._('Stop') }}"><i class="fa fa-stop fa-fw"></i></span>';
                } else {
                    html += '<span id="pfSvcStart" class="btn btn-sm btn-default" title="{{ lang._('Start') }}"><i class="fa fa-play fa-fw"></i></span>';
                }
                $('#service_status_container').html(html);
                $('#pfSvcStart').click(function() { svcAct('pfaliasdStart'); });
                $('#pfSvcRestart').click(function() { svcAct('pfaliasdRestart'); });
                $('#pfSvcStop').click(function() { svcAct('pfaliasdStop'); });
            });
        }
        function svcAct(act) {
            ajaxCall(url="/api/mosdns/service/" + act, sendData={}, callback=function(data, status) {
                setTimeout(refreshSvc, 1200);
            });
        }
        refreshSvc();
    });
</script>

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
