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

        function saveSection(formid, btn) {
            saveFormToEndpoint(url="/api/mosdns/settings/set", formid=formid,
                callback_ok=function() {
                    $("#responseMsg").removeClass("hidden")
                        .removeClass("alert-danger").addClass("alert-success")
                        .html("{{ lang._('Settings saved. Press Apply to activate.') }}");
                },
                callback_fail=function() {
                    $("#responseMsg").removeClass("hidden")
                        .removeClass("alert-success").addClass("alert-danger")
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
                $("#responseMsg").removeClass("hidden alert-danger").addClass("alert-info")
                    .html((data['response'] || status).toString().replace(/\n/g, "<br/>"));
                refreshStatus();
            });
        });

        function refreshStatus() {
            ajaxCall(url="/api/mosdns/service/status", sendData={}, callback=function(data, status) {
                $("#serviceStatus").html((data['response'] || status).toString().replace(/\n/g, "<br/>"));
            });
        }
        $("#refreshStatusAct").click(function() { refreshStatus(); });
        refreshStatus();
    });
</script>

<div class="content-box">
    <div class="col-md-12">
        <h4>{{ lang._('General') }}</h4>
        <p class="text-muted">{{ lang._('Enable the MosDNS forwarder and set its listen address.') }}</p>
    </div>
    <div class="col-md-12">
        {{ partial("layout_partials/base_form",['fields':generalForm,'id':'frm_GeneralSettings']) }}
    </div>
    <div class="col-md-12"><hr/>
        <button class="btn btn-primary" id="saveGeneralAct" type="button"><b>{{ lang._('Save') }}</b></button>
    </div>
</div>

<div class="content-box">
    <div class="col-md-12">
        <h4>{{ lang._('Forwarding') }}</h4>
        <p class="text-muted">{{ lang._('Remote upstreams are used for proxy domains (via optional SOCKS5), local upstreams for direct domains. Domain lists are matched against the files below, one file per line.') }}</p>
    </div>
    <div class="col-md-12">
        {{ partial("layout_partials/base_form",['fields':forwardForm,'id':'frm_ForwardSettings']) }}
    </div>
    <div class="col-md-12"><hr/>
        <button class="btn btn-primary" id="saveForwardAct" type="button"><b>{{ lang._('Save') }}</b></button>
    </div>
</div>

<div class="content-box">
    <div class="col-md-12">
        <h4>{{ lang._('pf Table Sync (pf_alias plugin)') }}</h4>
        <p class="text-muted">{{ lang._('Resolved A/AAAA records are pushed to the pf table via pf-aliasd. Requires the mosdns-pf binary with the pf_alias plugin.') }}</p>
    </div>
    <div class="col-md-12">
        {{ partial("layout_partials/base_form",['fields':pfaliasForm,'id':'frm_PfaliasSettings']) }}
    </div>
    <div class="col-md-12"><hr/>
        <button class="btn btn-primary" id="savePfaliasAct" type="button"><b>{{ lang._('Save') }}</b></button>
    </div>
</div>

<div class="content-box">
    <div class="col-md-12">
        <h4>{{ lang._('pf-aliasd Daemon') }}</h4>
        <p class="text-muted">{{ lang._('Receives DNS results over a Unix socket and writes them to pf tables with TTL expiry. flush_tables (comma separated) are emptied on daemon start.') }}</p>
    </div>
    <div class="col-md-12">
        {{ partial("layout_partials/base_form",['fields':pfaliasdForm,'id':'frm_PfaliasdSettings']) }}
    </div>
    <div class="col-md-12"><hr/>
        <button class="btn btn-primary" id="savePfaliasdAct" type="button"><b>{{ lang._('Save') }}</b></button>
    </div>
</div>

<div class="content-box">
    <div class="col-md-12">
        <button class="btn btn-primary" id="reconfigureAct" type="button">
            <b>{{ lang._('Apply') }}</b> <i id="reconfigureAct_progress"></i>
        </button>
        <button class="btn btn-default" id="refreshStatusAct" type="button">{{ lang._('Refresh status') }}</button>
    </div>
    <div class="col-md-12" style="margin-top: 10px;">
        <div id="responseMsg" class="alert hidden" role="alert"></div>
        <pre id="serviceStatus" style="margin-top: 10px;"></pre>
    </div>
</div>
