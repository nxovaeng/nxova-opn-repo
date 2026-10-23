{#
 # Copyright (C) 2026 nxovaeng
 # All rights reserved.
 #}

<script>
    function escHtml(s) {
        return $('<div>').text(s == null ? '' : String(s)).html();
    }

    $(document).ready(function() {
        window.__pings = {};
        window.__activeUuid = '';

        // ---- general settings ----
        mapDataToFormUI({'frm_GeneralSettings': "/api/xray/settings/get"}).done(function() {
            $('.selectpicker').selectpicker('refresh');
        });
        $("#saveGeneralAct").click(function() {
            saveFormToEndpoint(url="/api/xray/settings/set", formid='frm_GeneralSettings',
                callback_ok=function() {
                    $("#responseMsg").removeClass("hidden alert-danger alert-info").addClass("alert-success")
                        .html("设置已保存，点底部「应用」生效。");
                });
        });

        // ---- formatters ----
        var protoColors = {vless: 'label-primary', vmess: 'label-info', trojan: 'label-warning', shadowsocks: 'label-success'};
        var typeNames = {domain: '域名', ip: 'IP', source: '来源', port: '端口'};

        // ---- grids ----
        $("#grid-nodes").UIBootgrid({
            search: '/api/xray/settings/searchNodes',
            get: '/api/xray/settings/getNode/',
            set: '/api/xray/settings/setNode/',
            add: '/api/xray/settings/addNode/',
            del: '/api/xray/settings/delNode/',
            toggle: '/api/xray/settings/toggleNode/',
            formatters: {
                protocolFmt: function(column, row) {
                    var p = row.protocol || '';
                    return '<span class="label ' + (protoColors[p] || 'label-default') + '">' + escHtml(p) + '</span>';
                },
                sourceFmt: function(column, row) {
                    if (!row.sub_id || row.sub_id === 'manual') {
                        return '<span class="label label-default">手动</span>';
                    }
                    return '<span class="label label-default">订阅</span>';
                },
                latencyFmt: function(column, row) {
                    var rtt = window.__pings[row.uuid];
                    if (rtt === undefined) return '<span class="text-muted">—</span>';
                    if (rtt < 0) return '<span class="label label-danger">超时</span>';
                    var cls = rtt < 150 ? 'label-success' : (rtt < 300 ? 'label-warning' : 'label-danger');
                    return '<span class="label ' + cls + '">' + rtt + ' ms</span>';
                },
                activeFmt: function(column, row) {
                    if (row.uuid === window.__activeUuid) {
                        return '<i class="fa fa-star text-warning" title="活动节点"></i>';
                    }
                    return '<button type="button" class="btn btn-xs btn-link set-active" data-uuid="' + row.uuid + '" title="设为活动节点"><i class="fa fa-star-o"></i></button>';
                }
            }
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
            toggle: '/api/xray/settings/toggleRule/',
            formatters: {
                typeFmt: function(column, row) {
                    return typeNames[row.type] || row.type || '';
                },
                outboundFmt: function(column, row) {
                    var t = row.outbound_tag || '';
                    if (t === 'direct') return '<span class="label label-success">直连</span>';
                    if (t === 'block') return '<span class="label label-danger">拦截</span>';
                    if (t === '') return '<span class="label label-primary">默认节点</span>';
                    return '<span class="label label-info">' + escHtml(t) + '</span>';
                }
            }
        });
        $("#grid-subscriptions").UIBootgrid({
            search: '/api/xray/settings/searchSubscriptions',
            get: '/api/xray/settings/getSubscription/',
            add: '/api/xray/settings/addSubscription/',
            del: '/api/xray/settings/delSubscription/',
            formatters: {
                subUpdateFmt: function(column, row) {
                    return '<button type="button" class="btn btn-xs btn-default sub-update" data-uuid="' + row.uuid + '" title="拉取订阅并替换其节点"><i class="fa fa-refresh"></i> 更新</button>';
                }
            }
        });

        // ---- helpers ----
        function fetchAll(url) {
            var d = $.Deferred();
            ajaxCall(url=url, sendData={current: 1, rowCount: -1, searchPhrase: '', sort: {}}, callback=function(data, status) {
                d.resolve(data['rows'] || []);
            });
            return d.promise();
        }

        function setActive(uuid) {
            if (!uuid) return;
            ajaxCall(url="/api/xray/settings/setActiveNode/" + uuid, sendData={}, callback=function(data, status) {
                if (data['result'] === 'saved') {
                    window.__activeUuid = uuid;
                    updateActiveUI();
                    $("#responseMsg").removeClass("hidden alert-danger alert-info").addClass("alert-success")
                        .html("活动节点已切换，点底部「应用」生效。");
                }
            });
        }

        function updateActiveUI() {
            ajaxCall(url="/api/xray/settings/get", sendData={}, callback=function(data, status) {
                window.__activeUuid = (data['xray'] && data['xray']['general'] && data['xray']['general']['active_node']) || '';
                fetchAll('/api/xray/settings/searchNodes').done(function(rows) {
                    var $sel = $("#activeNodeSelect");
                    var cur = $sel.val();
                    $sel.empty();
                    var activeTag = '';
                    $.each(rows, function(i, r) {
                        $sel.append($('<option>').val(r.uuid).text(r.tag || r.uuid.substring(0, 8)));
                        if (r.uuid === window.__activeUuid) activeTag = r.tag;
                    });
                    if (window.__activeUuid) $sel.val(window.__activeUuid);
                    else if (cur) $sel.val(cur);
                    $("#activeNodeTag").text(activeTag || '未设置');
                    $("#grid-nodes").bootgrid("reload");
                });
            });
        }
        updateActiveUI();

        $("#setActiveAct").click(function() { setActive($("#activeNodeSelect").val()); });
        $(document).on('click', '.set-active', function() { setActive($(this).data('uuid')); });

        // ---- import nodes ----
        $("#importNodesAct").click(function() {
            var links = $("#importLinks").val();
            if (!links.trim()) return;
            ajaxCall(url="/api/xray/settings/importNodes", sendData={links: links, sub_id: 'manual'}, callback=function(data, status) {
                var $r = $("#importResult");
                if (data['result'] === 'saved') {
                    $r.removeClass("text-danger").addClass("text-success")
                      .text("成功导入 " + (data['added'] || 0) + " 个节点。");
                    $("#importLinks").val('');
                    $("#grid-nodes").bootgrid("reload");
                    updateActiveUI();
                } else {
                    $r.removeClass("text-success").addClass("text-danger")
                      .text("导入失败：" + (data['error'] || '没有可解析的链接'));
                }
            });
        });

        // ---- subscriptions ----
        function updateSub(uuid, done) {
            ajaxCall(url="/api/xray/settings/updateSubscription", sendData={uuid: uuid}, callback=function(data, status) {
                done(data);
            });
        }
        $(document).on('click', '.sub-update', function() {
            var uuid = $(this).data('uuid');
            var $r = $("#subResult");
            $r.removeClass("text-success text-danger").text("更新中…");
            updateSub(uuid, function(data) {
                if (data['result'] === 'saved') {
                    $r.addClass("text-success").text("订阅已更新，新增 " + (data['added'] || 0) + " 个节点，点底部「应用」生效。");
                    $("#grid-nodes").bootgrid("reload");
                    updateActiveUI();
                } else {
                    $r.addClass("text-danger").text("更新失败：" + (data['error'] || '拉取或解析失败'));
                }
            });
        });
        $("#updateAllSubsAct").click(function() {
            var $r = $("#subResult");
            fetchAll('/api/xray/settings/searchSubscriptions').done(function(rows) {
                if (!rows.length) { $r.text("没有订阅。"); return; }
                $r.removeClass("text-success text-danger").text("更新中…（0/" + rows.length + "）");
                var ok = 0, total = 0, chain = $.Deferred().resolve();
                $.each(rows, function(i, row) {
                    chain = chain.then(function() {
                        var d = $.Deferred();
                        updateSub(row.uuid, function(data) {
                            if (data['result'] === 'saved') { ok++; total += (data['added'] || 0); }
                            $r.text("更新中…（" + (i + 1) + "/" + rows.length + "）");
                            d.resolve();
                        });
                        return d.promise();
                    });
                });
                chain.done(function() {
                    $r.addClass("text-success").text("全部更新完成：" + ok + "/" + rows.length + " 个订阅，共 " + total + " 个节点，点底部「应用」生效。");
                    $("#grid-nodes").bootgrid("reload");
                    updateActiveUI();
                });
            });
        });

        // ---- ping ----
        $("#pingNodesAct").click(function() {
            var $btn = $(this);
            $btn.prop("disabled", true);
            ajaxCall(url="/api/xray/settings/pingNodes", sendData={uuids: []}, callback=function(data, status) {
                $btn.prop("disabled", false);
                window.__pings = data['pings'] || {};
                var total = 0, alive = 0, best = null;
                $.each(window.__pings, function(uuid, rtt) {
                    total++;
                    if (rtt >= 0) { alive++; if (best === null || rtt < best) best = rtt; }
                });
                $("#pingResult").text(total ? ("共 " + total + " 个节点，" + alive + " 个可达" + (best !== null ? "，最低延迟 " + best + " ms" : "") + "。") : "没有节点。");
                $("#grid-nodes").bootgrid("reload");
            });
        });

        // ---- apply ----
        $("#reconfigureAct").click(function() {
            $("#reconfigureAct_progress").addClass("fa fa-spinner fa-pulse");
            ajaxCall(url="/api/xray/service/reconfigure", sendData={}, callback=function(data, status) {
                $("#reconfigureAct_progress").removeClass("fa fa-spinner fa-pulse");
                var msg = data['status'] == 'ok' ? "配置已应用。" : (data['status_msg'] || "应用失败。");
                var cls = data['status'] == 'ok' ? "alert-success" : "alert-danger";
                $("#responseMsg").removeClass("hidden alert-success alert-danger alert-info").addClass(cls).html(escHtml(msg));
                refreshStatus();
                updateServiceControlUI('xray');
            });
        });

        // ---- preview / test ----
        $("#previewAct").click(function() {
            ajaxCall(url="/api/xray/service/preview", sendData={}, callback=function(data, status) {
                $("#configPreview").text(data['result'] == 'ok' ? JSON.stringify(data['config'], null, 2) : (data['error'] || '生成失败'));
            });
        });
        $("#testConfigAct").click(function() {
            ajaxCall(url="/api/xray/service/testConfig", sendData={}, callback=function(data, status) {
                var $m = $("#settingsMsg");
                if (data['result'] == 'ok') {
                    $m.removeClass("hidden alert-danger").addClass("alert-success").text("当前已生成的配置校验通过（xray -test）。");
                } else {
                    $m.removeClass("hidden alert-success").addClass("alert-danger").text("校验失败：" + (data['output'] || ''));
                }
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
                $("#serviceStatus").text("状态：" + (data['status'] || status));
            });
        }
        refreshStatus();
        updateServiceControlUI('xray');

        // ---- rule templates ----
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
            addTemplateRules([{type: 'domain', values: 'openai.com,chatgpt.com,anthropic.com,claude.ai,gemini.google.com', outbound_tag: ''}]);
        });
        $("#addTemplateMedia").click(function() {
            addTemplateRules([{type: 'domain', values: 'netflix.com,nflxvideo.net,disneyplus.com,youtube.com,googlevideo.com,hbo.com,spotify.com', outbound_tag: ''}]);
        });
        $("#addTemplateCN").click(function() {
            addTemplateRules([
                {type: 'domain', values: 'geosite:cn', outbound_tag: 'direct'},
                {type: 'ip', values: 'geoip:cn,geoip:private', outbound_tag: 'direct'}
            ]);
        });
        $("#addTemplateAds").click(function() {
            addTemplateRules([{type: 'domain', values: 'geosite:category-ads-all', outbound_tag: 'block'}]);
        });

        // ---- node dialog cascade (3x-ui style: protocol -> credentials, network/security -> stream fields) ----
        function nodeField(name) {
            return $('#DialogNode').find('input,select,textarea').filter(function() {
                return this.id && (this.id === name || this.id.endsWith('.' + name));
            });
        }
        function showRow($f, show) { if ($f.length) $f.closest('tr').toggle(!!show); }
        function cascadeNode() {
            var proto = nodeField('protocol').val() || '';
            var net = nodeField('network').val() || '';
            var sec = nodeField('security').val() || '';
            showRow(nodeField('user_id'), proto === 'vless' || proto === 'vmess');
            showRow(nodeField('password'), proto === 'trojan' || proto === 'shadowsocks');
            showRow(nodeField('ss_method'), proto === 'shadowsocks');
            showRow(nodeField('vmess_cipher'), proto === 'vmess');
            showRow(nodeField('flow'), proto === 'vless');
            showRow(nodeField('alter_id'), proto === 'vmess');
            showRow(nodeField('path'), net === 'ws' || net === 'xhttp' || net === 'grpc');
            showRow(nodeField('host'), net === 'ws' || net === 'xhttp');
            showRow(nodeField('sni'), sec === 'tls' || sec === 'reality');
            showRow(nodeField('fingerprint'), sec === 'tls' || sec === 'reality');
            showRow(nodeField('allow_insecure'), sec === 'tls');
            showRow(nodeField('public_key'), sec === 'reality');
            showRow(nodeField('short_id'), sec === 'reality');
            showRow(nodeField('spider_x'), sec === 'reality');
        }
        $(document).on('change', '#DialogNode select', cascadeNode);
        $(document).on('shown.bs.modal', '#DialogNode', function() { setTimeout(cascadeNode, 60); });
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
        <div class="alert alert-info" style="padding: 8px 12px; margin-bottom: 10px;">
            <div class="pull-right">
                <select id="activeNodeSelect" class="form-control input-sm" style="width: auto; display: inline-block;"></select>
                <button class="btn btn-primary btn-sm" id="setActiveAct" type="button">切换</button>
                <button class="btn btn-default btn-sm" id="pingNodesAct" type="button">全部测速</button>
            </div>
            <div style="line-height: 30px;">
                当前活动节点：<b id="activeNodeTag">未设置</b>
                <span id="pingResult" class="text-muted" style="margin-left: 10px;"></span>
            </div>
            <div class="clearfix"></div>
            <small class="text-muted">活动节点是未命中路由规则时的默认出站；切换后点底部「应用」生效。也可以点节点行里的 ☆ 直接设为活动。</small>
        </div>
        <table id="grid-nodes" class="table table-condensed table-hover table-striped" data-editDialog="DialogNode">
            <thead>
                <tr>
                    <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">ID</th>
                    <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">启用</th>
                    <th data-column-id="tag" data-type="string">标签</th>
                    <th data-column-id="protocol" data-type="string" data-formatter="protocolFmt">协议</th>
                    <th data-column-id="address" data-type="string">地址</th>
                    <th data-column-id="port" data-type="string" data-width="6em">端口</th>
                    <th data-column-id="network" data-type="string" data-width="6em">传输</th>
                    <th data-column-id="security" data-type="string" data-width="6em">安全</th>
                    <th data-column-id="sub_id" data-type="string" data-width="6em" data-formatter="sourceFmt">来源</th>
                    <th data-column-id="latency" data-type="string" data-width="7em" data-sortable="false" data-formatter="latencyFmt">延迟</th>
                    <th data-column-id="active" data-type="string" data-width="4em" data-sortable="false" data-formatter="activeFmt">活动</th>
                    <th data-column-id="commands" data-width="7em" data-formatter="commands" data-sortable="false">操作</th>
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

        <div class="panel panel-default" style="margin-top: 15px;">
            <div class="panel-heading"><b>导入节点</b> <span class="text-muted">— 粘贴 vless / vmess / trojan / ss 链接，一行一个；也可以整段粘贴订阅内容（明文或 Base64）</span></div>
            <div class="panel-body">
                <textarea id="importLinks" rows="4" class="form-control" placeholder="vless://…&#10;vmess://…"></textarea>
                <div style="margin-top: 10px;">
                    <button class="btn btn-primary btn-sm" id="importNodesAct" type="button">导入</button>
                    <span id="importResult" style="margin-left: 10px;"></span>
                </div>
            </div>
        </div>

        <div class="panel panel-default">
            <div class="panel-heading"><b>订阅管理</b> <span class="text-muted">— 更新会拉取订阅并替换该订阅的全部节点</span></div>
            <div class="panel-body">
                <table id="grid-subscriptions" class="table table-condensed table-hover table-striped" data-editDialog="DialogSubscription">
                    <thead>
                        <tr>
                            <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">ID</th>
                            <th data-column-id="name" data-type="string">名称</th>
                            <th data-column-id="url" data-type="string">订阅链接</th>
                            <th data-column-id="update" data-type="string" data-width="8em" data-sortable="false" data-formatter="subUpdateFmt">更新</th>
                            <th data-column-id="commands" data-width="7em" data-formatter="commands" data-sortable="false">操作</th>
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
                <div>
                    <button class="btn btn-default btn-sm" id="updateAllSubsAct" type="button">全部更新</button>
                    <span id="subResult" style="margin-left: 10px;"></span>
                </div>
            </div>
        </div>
    </div>
    <div id="inbounds" class="tab-pane fade">
        <p class="text-muted">内置固定入站：hev-socks-in（127.0.0.1:10808，给 tun2socks 用）、dns-in（127.0.0.1:10853）。下面可加自定义入站，如给局域网开一个带认证的 socks。</p>
        <table id="grid-inbounds" class="table table-condensed table-hover table-striped" data-editDialog="DialogInbound">
            <thead>
                <tr>
                    <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">ID</th>
                    <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">启用</th>
                    <th data-column-id="tag" data-type="string">标签</th>
                    <th data-column-id="protocol" data-type="string">协议</th>
                    <th data-column-id="listen" data-type="string">监听</th>
                    <th data-column-id="port" data-type="string">端口</th>
                    <th data-column-id="commands" data-width="7em" data-formatter="commands" data-sortable="false">操作</th>
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
            <button class="btn btn-default btn-xs" id="addTemplateAI" type="button">＋ AI 服务走代理</button>
            <button class="btn btn-default btn-xs" id="addTemplateMedia" type="button">＋ 流媒体走代理</button>
            <button class="btn btn-default btn-xs" id="addTemplateCN" type="button">＋ 国内直连（geosite/geoip）</button>
            <button class="btn btn-default btn-xs" id="addTemplateAds" type="button">＋ 广告拦截</button>
        </p>
        <p class="text-muted">规则按表格顺序自上而下匹配，命中即止；都没命中走活动节点。出站留空 = 默认节点，也可以填某个节点标签做定向分流。设置里开启「共享规则组」后，MosDNS「规则」页的规则组会在应用时自动转换并排在本表规则之后（阻止 &gt; 直连 &gt; 代理）。</p>
        <table id="grid-rules" class="table table-condensed table-hover table-striped" data-editDialog="DialogRule">
            <thead>
                <tr>
                    <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">ID</th>
                    <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">启用</th>
                    <th data-column-id="type" data-type="string" data-width="6em" data-formatter="typeFmt">类型</th>
                    <th data-column-id="values" data-type="string">匹配值</th>
                    <th data-column-id="outbound_tag" data-type="string" data-formatter="outboundFmt">出站</th>
                    <th data-column-id="commands" data-width="7em" data-formatter="commands" data-sortable="false">操作</th>
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
                    <td><button class="btn btn-primary" id="saveGeneralAct" type="button"><b>保存</b></button></td>
                    <td></td>
                </tr>
            </tbody>
        </table>
        <hr/>
        <button class="btn btn-default" id="previewAct" type="button">预览生成的配置</button>
        <button class="btn btn-default" id="testConfigAct" type="button">校验当前配置</button>
        <div id="settingsMsg" class="alert hidden" role="alert" style="margin-top: 10px;"></div>
        <pre id="configPreview" style="margin-top:10px; max-height:400px; overflow:auto;"></pre>
    </div>
    <div id="logs" class="tab-pane fade">
        <button class="btn btn-default btn-sm" id="refreshLogAct" type="button">刷新</button>
        <pre id="xrayLog" style="margin-top:10px; max-height:500px; overflow:auto; background:#000; color:#0f0;"></pre>
    </div>
</div>

<div class="content-box" style="margin-top: 20px;">
    <div class="col-md-12">
        <button class="btn btn-primary" id="reconfigureAct" type="button">
            <b>应用</b> <i id="reconfigureAct_progress"></i>
        </button>
        <span id="serviceStatus" class="text-muted" style="margin-left: 10px;"></span>
    </div>
    <div class="col-md-12" style="margin-top: 10px;">
        <div id="responseMsg" class="alert hidden" role="alert"></div>
    </div>
</div>

{{ partial("layout_partials/base_dialog",['fields':nodeForm,'id':'DialogNode','label':lang._('编辑节点')])}}
{{ partial("layout_partials/base_dialog",['fields':inboundForm,'id':'DialogInbound','label':lang._('编辑入站')])}}
{{ partial("layout_partials/base_dialog",['fields':ruleForm,'id':'DialogRule','label':lang._('编辑规则')])}}
{{ partial("layout_partials/base_dialog",['fields':subscriptionForm,'id':'DialogSubscription','label':lang._('编辑订阅')])}}
