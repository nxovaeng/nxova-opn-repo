{#
 # Copyright (C) 2026 nxovaeng
 # All rights reserved.
 #}

<script>
    $(document).ready(function() {
        var data_get_map = {
            'frm_GeneralSettings': "/api/mosdns/settings/get",
            'frm_ForwardSettings': "/api/mosdns/settings/get",
            'frm_PfaliasSettings': "/api/mosdns/settings/get",
            'frm_PfaliasdSettings': "/api/mosdns/settings/get"
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
        $("#savePfaliasdAct").click(function() { saveSection('frm_PfaliasdSettings'); });

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

<div class="content-box">
    <div class="col-md-12">
        <div class="pull-right">
            <button class="btn btn-primary" id="reconfigureAct" type="button">
                <b>{{ lang._('Apply') }}</b> <i id="reconfigureAct_progress"></i>
            </button>
        </div>
        <h4>{{ lang._('MosDNS') }}</h4>
        <p class="text-muted">
            {{ lang._('Dynamic DNS forwarder with pf table sync.') }}
            <span id="serviceStatus"></span>
        </p>
    </div>
    <div class="col-md-12">
        <div id="responseMsg" class="alert hidden" role="alert"></div>
    </div>
</div>

<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
    <li class="active"><a data-toggle="tab" href="#general">{{ lang._('General') }}</a></li>
    <li><a data-toggle="tab" href="#forward">{{ lang._('Forwarding') }}</a></li>
    <li><a data-toggle="tab" href="#pfalias">{{ lang._('PF table sync') }}</a></li>
    <li><a data-toggle="tab" href="#pfaliasd">{{ lang._('pf-aliasd') }}</a></li>
</ul>
<div class="tab-content content-box tab-content">
    <div id="general" class="tab-pane fade in active">
        <p class="text-muted">{{ lang._('Enable the MosDNS forwarder and set its listen address.') }}</p>
        {{ partial("layout_partials/base_form",['fields':generalForm,'id':'frm_GeneralSettings']) }}
        <hr/>
        <button class="btn btn-primary" id="saveGeneralAct" type="button"><b>{{ lang._('Save') }}</b></button>
    </div>
    <div id="forward" class="tab-pane fade">
        <p class="text-muted">{{ lang._('Remote upstreams are used for proxy domains (via optional SOCKS5), local upstreams for direct domains. Lists are comma separated.') }}</p>
        {{ partial("layout_partials/base_form",['fields':forwardForm,'id':'frm_ForwardSettings']) }}
        <hr/>
        <button class="btn btn-primary" id="saveForwardAct" type="button"><b>{{ lang._('Save') }}</b></button>
    </div>
    <div id="pfalias" class="tab-pane fade">
        <p class="text-muted">{{ lang._('Resolved A/AAAA records are pushed to the pf table via pf-aliasd. Requires the mosdns-pf binary with the pf_alias plugin.') }}</p>
        {{ partial("layout_partials/base_form",['fields':pfaliasForm,'id':'frm_PfaliasSettings']) }}
        <hr/>
        <button class="btn btn-primary" id="savePfaliasAct" type="button"><b>{{ lang._('Save') }}</b></button>
    </div>
    <div id="pfaliasd" class="tab-pane fade">
        <p class="text-muted">{{ lang._('Receives DNS results over a Unix socket and writes them to pf tables with TTL expiry. Flush tables (comma separated) are emptied on daemon start.') }}</p>
        {{ partial("layout_partials/base_form",['fields':pfaliasdForm,'id':'frm_PfaliasdSettings']) }}
        <hr/>
        <button class="btn btn-primary" id="savePfaliasdAct" type="button"><b>{{ lang._('Save') }}</b></button>
    </div>
</div>
