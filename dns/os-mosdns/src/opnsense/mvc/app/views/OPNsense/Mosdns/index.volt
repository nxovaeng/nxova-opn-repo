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

        // ---- rules ----
        function loadRuleList() {
            ajaxCall(url="/api/mosdns/service/listRules", sendData={}, callback=function(data, status) {
                var sel = $("#ruleFileSelect").empty();
                $.each(data['files'] || [], function(i, f) {
                    sel.append($("<option>").val(f['name']).text(f['name'] + " (" + f['count'] + ")" + (f['editable'] ? "" : " [read-only]")));
                });
                loadRuleContent();
            });
        }
        function loadRuleContent() {
            var name = $("#ruleFileSelect").val();
            if (!name) return;
            ajaxCall(url="/api/mosdns/service/getRule/" + name, sendData={}, callback=function(data, status) {
                $("#ruleFileContent").val(data['content'] || '');
                var editable = !/\[read-only\]/.test($("#ruleFileSelect option:selected").text());
                $("#ruleFileContent").prop("disabled", !editable);
                $("#saveRuleFileAct").prop("disabled", !editable);
            });
        }
        $("#ruleFileSelect").change(loadRuleContent);
        $("#saveRuleFileAct").click(function() {
            var name = $("#ruleFileSelect").val();
            ajaxCall(url="/api/mosdns/service/setRule/" + name, sendData={content: $("#ruleFileContent").val()}, callback=function(data, status) {
                $("#ruleFileMsg").text(data['result'] == 'saved' ? "{{ lang._('Saved.') }}" : "{{ lang._('Failed.') }}");
                loadRuleList();
            });
        });
        loadRuleList();

        // ---- domain test ----
        $("#testDomainAct").click(function() {
            var domain = $("#testDomain").val().trim();
            if (!domain) return;
            ajaxCall(url="/api/mosdns/service/testDomain", sendData={domain: domain}, callback=function(data, status) {
                if (data['result'] != 'ok') {
                    $("#testResult").html('<div class="alert alert-danger">' + (data['error'] || 'failed') + '</div>');
                    return;
                }
                var badge = data['action'] == 'proxy' ? 'label-warning' : (data['action'] == 'block' ? 'label-danger' : 'label-success');
                var html = '<h4><span class="label ' + badge + '">' + data['action'] + '</span> <small>' + data['domain'] + '</small></h4>';
                html += '<p>' + data['explain'] + '</p>';
                if (data['matched_rule']) html += '<p class="text-muted">matched: <code>' + data['matched_rule'] + '</code> (' + data['matched_file'] + ')</p>';
                if (data['sync_pf']) html += '<p class="text-muted">will sync to pf table</p>';
                $("#testResult").html(html);
            });
        });

        // ---- logs ----
        function refreshLog(target) {
            ajaxCall(url="/api/mosdns/service/log/" + target, sendData={lines: 100}, callback=function(data, status) {
                $("#mosdnsLog").text(data['log'] || '');
            });
        }
        $("#refreshMosdnsLog").click(function() { refreshLog('mosdns'); });
        $("#refreshAliasdLog").click(function() { refreshLog('aliasd'); });
    });
</script>

<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
    <li class="active"><a data-toggle="tab" href="#general">{{ lang._('General') }}</a></li>
    <li><a data-toggle="tab" href="#forward">{{ lang._('Forwarding') }}</a></li>
    <li><a data-toggle="tab" href="#pfalias">{{ lang._('PF table sync') }}</a></li>
    <li><a data-toggle="tab" href="#pfaliasd">{{ lang._('pf-aliasd') }}</a></li>
    <li><a data-toggle="tab" href="#rules">{{ lang._('Rules') }}</a></li>
    <li><a data-toggle="tab" href="#test">{{ lang._('Test') }}</a></li>
    <li><a data-toggle="tab" href="#logs">{{ lang._('Logs') }}</a></li>
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
    <div id="pfaliasd" class="tab-pane fade">
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
    <div id="rules" class="tab-pane fade">
        <p class="text-muted">{{ lang._('Edit custom rule lists. Authority lists (cn.txt, gfw.txt) are read-only.') }}</p>
        <div class="form-group">
            <select id="ruleFileSelect" class="form-control" style="max-width:300px;"></select>
        </div>
        <textarea id="ruleFileContent" rows="15" class="form-control" style="font-family:monospace;"></textarea>
        <div style="margin-top:10px;">
            <button class="btn btn-primary btn-sm" id="saveRuleFileAct" type="button">{{ lang._('Save list') }}</button>
            <span id="ruleFileMsg" class="text-muted" style="margin-left:10px;"></span>
        </div>
    </div>
    <div id="test" class="tab-pane fade">
        <p class="text-muted">{{ lang._('Simulate the routing decision for a domain without real queries.') }}</p>
        <div class="form-inline">
            <input type="text" id="testDomain" class="form-control" placeholder="example.com" style="min-width:300px;"/>
            <button class="btn btn-primary btn-sm" id="testDomainAct" type="button">{{ lang._('Test') }}</button>
        </div>
        <div id="testResult" style="margin-top:15px;"></div>
    </div>
    <div id="logs" class="tab-pane fade">
        <p>
            <button class="btn btn-default btn-sm" id="refreshMosdnsLog" type="button">mosdns {{ lang._('Refresh') }}</button>
            <button class="btn btn-default btn-sm" id="refreshAliasdLog" type="button">pf-aliasd {{ lang._('Refresh') }}</button>
        </p>
        <pre id="mosdnsLog" style="max-height:400px; overflow:auto; background:#000; color:#0f0;"></pre>
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
