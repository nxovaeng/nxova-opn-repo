{#
 # Copyright (C) 2026 nxovaeng
 # All rights reserved.
 #}

<script>
    $(document).ready(function() {
        // ---- general settings ----
        mapDataToFormUI({'frm_GeneralSettings': "/api/xray/settings/get"}).done(function() {
            $('.selectpicker').selectpicker('refresh');
        });
        $("#saveGeneralAct").click(function() {
            saveFormToEndpoint(url="/api/xray/settings/set", formid='frm_GeneralSettings',
                callback_ok=function() {
                    $("#responseMsg").removeClass("hidden").removeClass("alert-danger alert-info").addClass("alert-success")
                        .html("{{ lang._('Settings saved. Press Apply to activate.') }}");
                });
        });

        // ---- grids ----
        $("#grid-nodes").UIBootgrid({
            search: '/api/xray/settings/searchNodes',
            get: '/api/xray/settings/getNode/',
            set: '/api/xray/settings/setNode/',
            add: '/api/xray/settings/addNode/',
            del: '/api/xray/settings/delNode/',
            toggle: '/api/xray/settings/toggleNode/'
        });
        $("#grid-inbounds").UIBootgrid({
            search: '/api/xray/settings/searchInbounds',
            get: '/api/xray/settings/getInbound/',
            set: '/api/xray/settings/setInbound/',
            add: '/api/xray/settings/addInbound/',
            del: '/api/xray/settings/delInbound/',
            toggle: '/api/xray/settings/toggleInbound/'
        });
        $("#grid-rules").UIBootgrid({
            search: '/api/xray/settings/searchRules',
            get: '/api/xray/settings/getRule/',
            set: '/api/xray/settings/setRule/',
            add: '/api/xray/settings/addRule/',
            del: '/api/xray/settings/delRule/',
            toggle: '/api/xray/settings/toggleRule/'
        });
        $("#grid-subscriptions").UIBootgrid({
            search: '/api/xray/settings/searchSubscriptions',
            get: '/api/xray/settings/getSubscription/',
            add: '/api/xray/settings/addSubscription/',
            del: '/api/xray/settings/delSubscription/'
        });

        function updateActiveBadge() {
            ajaxCall(url="/api/xray/settings/get", sendData={}, callback=function(data, status) {
                var active = (data['xray'] && data['xray']['general'] && data['xray']['general']['active_node']) || '';
                $("#activeNodeBadge").text(active ? "{{ lang._('Active') }}: " + active.substring(0, 8) : "{{ lang._('No active node') }}");
            });
        }
        updateActiveBadge();

        // ---- import nodes ----
        $("#importNodesAct").click(function() {
            var links = $("#importLinks").val();
            if (!links.trim()) return;
            ajaxCall(url="/api/xray/settings/importNodes", sendData={links: links, sub_id: 'manual'}, callback=function(data, status) {
                $("#importResult").text(JSON.stringify(data));
                $("#grid-nodes").bootgrid("reload");
                updateActiveBadge();
            });
        });

        // ---- ping ----
        $("#pingNodesAct").click(function() {
            ajaxCall(url="/api/xray/settings/pingNodes", sendData={uuids: []}, callback=function(data, status) {
                var html = "";
                $.each(data['pings'] || {}, function(uuid, rtt) {
                    html += uuid.substring(0, 8) + ": " + (rtt >= 0 ? rtt + " ms" : "fail") + "<br/>";
                });
                $("#pingResult").html(html || "{{ lang._('No nodes') }}");
            });
        });

        // ---- apply ----
        $("#reconfigureAct").click(function() {
            $("#reconfigureAct_progress").addClass("fa fa-spinner fa-pulse");
            ajaxCall(url="/api/xray/service/reconfigure", sendData={}, callback=function(data, status) {
                $("#reconfigureAct_progress").removeClass("fa fa-spinner fa-pulse");
                var msg = data['status'] == 'ok' ? "{{ lang._('Configuration applied.') }}" : (data['status_msg'] || "{{ lang._('Apply failed.') }}");
                var cls = data['status'] == 'ok' ? "alert-success" : "alert-danger";
                $("#responseMsg").removeClass("hidden alert-success alert-danger alert-info").addClass(cls).html(msg);
                refreshStatus();
            });
        });

        // ---- preview ----
        $("#previewAct").click(function() {
            ajaxCall(url="/api/xray/service/preview", sendData={}, callback=function(data, status) {
                $("#configPreview").text(data['result'] == 'ok' ? JSON.stringify(data['config'], null, 2) : (data['error'] || 'failed'));
            });
        });

        // ---- logs ----
        function refreshLog() {
            ajaxCall(url="/api/xray/service/log", sendData={lines: 100}, callback=function(data, status) {
                $("#xrayLog").text(data['log'] || '');
            });
        }
        $("#refreshLogAct").click(refreshLog);

        function refreshStatus() {
            ajaxCall(url="/api/xray/service/status", sendData={}, callback=function(data, status) {
                $("#serviceStatus").text("{{ lang._('Status') }}: " + (data['status'] || status));
            });
        }
        refreshStatus();

        // rule templates
        function addTemplateRules(templates) {
            var chain = $.Deferred().resolve();
            templates.forEach(function(t) {
                chain = chain.then(function() {
                    return ajaxCall(url="/api/xray/settings/addRule", sendData={rule: $.extend({enabled: '1'}, t)});
                });
            });
            chain.done(function() { $("#grid-rules").bootgrid("reload"); });
        }
        $("#addTemplateAI").click(function() {
            addTemplateRules([{type: 'domain', values: 'openai.com,chatgpt.com,anthropic.com,claude.ai', outbound_tag: ''}]);
        });
        $("#addTemplateMedia").click(function() {
            addTemplateRules([{type: 'domain', values: 'netflix.com,nflxvideo.net,disneyplus.com,youtube.com,googlevideo.com', outbound_tag: ''}]);
        });
    });
</script>

<div id="svc-btns" class="btn-group pull-right" role="group" aria-label="xray" style="display:none;">
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
        var $h1 = $('h1').first();
        if ($h1.length) { $('#svc-btns').show().detach().appendTo($h1); }
        else { $('#svc-btns').show(); }
    });
</script>
<script>
    $(document).ready(function() {
        function refreshSvcStatus() {
            ajaxCall(url="/api/xray/service/status", sendData={}, callback=function(data, status) {
                var running = data['status'] == 'running';
                $("#svc-start").prop("disabled", running).toggleClass("btn-success", !running).toggleClass("btn-default", running);
                $("#svc-stop").prop("disabled", !running);
                $("#svc-restart").prop("disabled", !running);
            });
        }
        $("#svc-start").click(function() {
            ajaxCall(url="/api/xray/service/start", sendData={}, callback=function(data, status) {
                setTimeout(refreshSvcStatus, 1500);
            });
        });
        $("#svc-restart").click(function() {
            ajaxCall(url="/api/xray/service/restart", sendData={}, callback=function(data, status) {
                setTimeout(refreshSvcStatus, 1500);
            });
        });
        $("#svc-stop").click(function() {
            ajaxCall(url="/api/xray/service/stop", sendData={}, callback=function(data, status) {
                setTimeout(refreshSvcStatus, 1500);
            });
        });
        refreshSvcStatus();
    });
</script>

<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
    <li class="active"><a data-toggle="tab" href="#nodes">节点</a></li>
    <li><a data-toggle="tab" href="#inbounds">入站</a></li>
    <li><a data-toggle="tab" href="#routing">路由</a></li>
    <li><a data-toggle="tab" href="#settings">设置</a></li>
    <li><a data-toggle="tab" href="#logs">日志</a></li>
</ul>
<div class="tab-content content-box tab-content">
    <div id="nodes" class="tab-pane fade in active">
        <p>
            <span id="activeNodeBadge" class="label label-info"></span>
            <button class="btn btn-default btn-xs" id="pingNodesAct" type="button">{{ lang._('Ping all') }}</button>
        </p>
        <div id="pingResult" class="text-muted" style="margin-bottom:10px;"></div>
        <table id="grid-nodes" class="table table-condensed table-hover table-striped" data-editDialog="DialogNode">
            <thead>
                <tr>
                    <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">{{ lang._('ID') }}</th>
                    <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">{{ lang._('Enabled') }}</th>
                    <th data-column-id="tag" data-type="string">{{ lang._('Tag') }}</th>
                    <th data-column-id="protocol" data-type="string">{{ lang._('Protocol') }}</th>
                    <th data-column-id="address" data-type="string">{{ lang._('Address') }}</th>
                    <th data-column-id="port" data-type="string">{{ lang._('Port') }}</th>
                    <th data-column-id="commands" data-width="7em" data-formatter="commands" data-sortable="false">{{ lang._('Commands') }}</th>
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
        <hr/>
        <h5>{{ lang._('Import nodes') }}</h5>
        <p class="text-muted">{{ lang._('Paste vless/vmess/trojan/ss links, one per line.') }}</p>
        <textarea id="importLinks" rows="4" class="form-control"></textarea>
        <div style="margin-top:10px;">
            <button class="btn btn-primary btn-sm" id="importNodesAct" type="button">{{ lang._('Import') }}</button>
            <span id="importResult" class="text-muted" style="margin-left:10px;"></span>
        </div>
        <hr/>
        <h5>{{ lang._('Subscriptions') }}</h5>
        <table id="grid-subscriptions" class="table table-condensed table-hover table-striped" data-editDialog="DialogSubscription">
            <thead>
                <tr>
                    <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">{{ lang._('ID') }}</th>
                    <th data-column-id="name" data-type="string">{{ lang._('Name') }}</th>
                    <th data-column-id="url" data-type="string">{{ lang._('URL') }}</th>
                    <th data-column-id="commands" data-width="7em" data-formatter="commands" data-sortable="false">{{ lang._('Commands') }}</th>
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
    <div id="inbounds" class="tab-pane fade">
        <p class="text-muted">{{ lang._('Built-in: hev-socks-in (127.0.0.1:10808), dns-in (127.0.0.1:10853). Add custom inbounds below.') }}</p>
        <table id="grid-inbounds" class="table table-condensed table-hover table-striped" data-editDialog="DialogInbound">
            <thead>
                <tr>
                    <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">{{ lang._('ID') }}</th>
                    <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">{{ lang._('Enabled') }}</th>
                    <th data-column-id="tag" data-type="string">{{ lang._('Tag') }}</th>
                    <th data-column-id="protocol" data-type="string">{{ lang._('Protocol') }}</th>
                    <th data-column-id="listen" data-type="string">{{ lang._('Listen') }}</th>
                    <th data-column-id="port" data-type="string">{{ lang._('Port') }}</th>
                    <th data-column-id="commands" data-width="7em" data-formatter="commands" data-sortable="false">{{ lang._('Commands') }}</th>
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
    <div id="routing" class="tab-pane fade">
        <p>
            <button class="btn btn-default btn-xs" id="addTemplateAI" type="button">{{ lang._('Add AI template') }}</button>
            <button class="btn btn-default btn-xs" id="addTemplateMedia" type="button">{{ lang._('Add streaming template') }}</button>
        </p>
        <table id="grid-rules" class="table table-condensed table-hover table-striped" data-editDialog="DialogRule">
            <thead>
                <tr>
                    <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">{{ lang._('ID') }}</th>
                    <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">{{ lang._('Enabled') }}</th>
                    <th data-column-id="type" data-type="string">{{ lang._('Type') }}</th>
                    <th data-column-id="values" data-type="string">{{ lang._('Values') }}</th>
                    <th data-column-id="outbound_tag" data-type="string">{{ lang._('Outbound') }}</th>
                    <th data-column-id="commands" data-width="7em" data-formatter="commands" data-sortable="false">{{ lang._('Commands') }}</th>
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
                    <td><button class="btn btn-primary" id="saveGeneralAct" type="button"><b>{{ lang._('Save') }}</b></button></td>
                    <td></td>
                </tr>
            </tbody>
        </table>
        <hr/>
        <button class="btn btn-default" id="previewAct" type="button">{{ lang._('Preview generated config') }}</button>
        <pre id="configPreview" style="margin-top:10px; max-height:400px; overflow:auto;"></pre>
    </div>
    <div id="logs" class="tab-pane fade">
        <button class="btn btn-default btn-sm" id="refreshLogAct" type="button">{{ lang._('Refresh') }}</button>
        <pre id="xrayLog" style="margin-top:10px; max-height:500px; overflow:auto; background:#000; color:#0f0;"></pre>
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

{{ partial("layout_partials/base_dialog",['fields':nodeForm,'id':'DialogNode','label':lang._('Edit node')])}}
{{ partial("layout_partials/base_dialog",['fields':inboundForm,'id':'DialogInbound','label':lang._('Edit inbound')])}}
{{ partial("layout_partials/base_dialog",['fields':ruleForm,'id':'DialogRule','label':lang._('Edit rule')])}}
{{ partial("layout_partials/base_dialog",['fields':subscriptionForm,'id':'DialogSubscription','label':lang._('Edit subscription')])}}
