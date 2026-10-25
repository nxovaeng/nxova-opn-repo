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
        window.__subCounts = {};
        window.__subCountsLoaded = false;
        window.__activeUuid = '';

        // ---- validation error banner (P0-2) ----
        function refreshValidationBanner() {
            ajaxCall(url="/api/xray/service/getValidationError", sendData={}, callback=function(data, status) {
                var err = (data['error'] || '').trim();
                if (err) {
                    $("#validationBanner").removeClass("hidden").text("上次配置生成失败（旧配置仍在运行）：" + err);
                } else {
                    $("#validationBanner").addClass("hidden").text("");
                }
            });
        }
        refreshValidationBanner();

        // ---- formatters ----
        var protoColors = {vless: 'label-primary', vmess: 'label-info', trojan: 'label-warning', shadowsocks: 'label-success'};

        // ---- grids ----
        $("#grid-nodes").UIBootgrid({
            search: '/api/xray/settings/searchNodes',
            get: '/api/xray/settings/getNode/',
            set: '/api/xray/settings/setNode/',
            add: '/api/xray/settings/addNode/',
            del: '/api/xray/settings/delNode/',
            toggle: '/api/xray/settings/toggleNode/',
            options: {
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
                    },
                    pingFmt: function(column, row) {
                        return '<button type="button" class="btn btn-xs btn-default node-ping" data-uuid="' + row.uuid + '" data-tag="' + escHtml(row.tag || row.uuid.substring(0, 8)) + '">连通测试</button>';
                    },
                    probeFmt: function(column, row) {
                        return '<button type="button" class="btn btn-xs btn-default node-probe" data-uuid="' + row.uuid + '" data-tag="' + escHtml(row.tag || row.uuid.substring(0, 8)) + '">出口探测</button>';
                    }
                }
            }        });
        $("#grid-subscriptions").UIBootgrid({
            search: '/api/xray/settings/searchSubscriptions',
            get: '/api/xray/settings/getSubscription/',
            add: '/api/xray/settings/addSubscription/',
            del: '/api/xray/settings/delSubscription/',
            options: {
                formatters: {
                    subUpdateFmt: function(column, row) {
                        return '<button type="button" class="btn btn-xs btn-default sub-update" data-uuid="' + row.uuid + '" title="拉取订阅并替换其节点"><i class="fa fa-refresh"></i> 更新</button>';
                    },
                    subCountFmt: function(column, row) {
                        if (!window.__subCountsLoaded) return '<span class="text-muted">—</span>';
                        return String(window.__subCounts[row.uuid] || 0);
                    }
                }
            }        });

        // ---- helpers ----
        function fetchAll(url) {
            var d = $.Deferred();
            ajaxCall(url=url, sendData={current: 1, rowCount: -1, searchPhrase: '', sort: {}}, callback=function(data, status) {
                d.resolve(data['rows'] || []);
            });
            return d.promise();
        }

        // ---- subscription node counts (a node's sub_id is its subscription uuid) ----
        function refreshSubCounts() {
            fetchAll('/api/xray/settings/searchNodes').done(function(rows) {
                var counts = {};
                $.each(rows, function(i, r) {
                    if (r.sub_id && r.sub_id !== 'manual') {
                        counts[r.sub_id] = (counts[r.sub_id] || 0) + 1;
                    }
                });
                window.__subCounts = counts;
                window.__subCountsLoaded = true;
                $("#grid-subscriptions").bootgrid("reload");
            });
        }
        refreshSubCounts();
        $('a[href="#subscriptions"]').on('shown.bs.tab', function() { refreshSubCounts(); });

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
            ajaxCall(url="/api/xray/settings/getActiveNode", sendData={}, callback=function(data, status) {
                window.__activeUuid = (data && data['uuid']) || '';
                var activeTag = (data && data['tag']) || '';
                $("#activeNodeTag").text(activeTag || '未设置');
                $("#grid-nodes").bootgrid("reload");
            });
        }
        updateActiveUI();

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
                    var msg = "订阅已更新，新增 " + (data['added'] || 0) + " 个，更新 " + (data['updated'] || 0) + " 个，删除 " + (data['removed'] || 0) + " 个。";
                    if (data['reloaded']) {
                        msg += "命中配置的节点有变化，已自动重载生效。";
                    } else if (data['warning']) {
                        msg += data['warning'];
                    } else if (data['reload_error']) {
                        msg += data['reload_error'];
                    } else {
                        msg += "点底部「应用」生效。";
                    }
                    $r.addClass("text-success").text(msg);
                    $("#grid-nodes").bootgrid("reload");
                    updateActiveUI();
                    refreshSubCounts();
                    refreshValidationBanner();
                } else {
                    $r.addClass("text-danger").text("更新失败：" + (data['error'] || '拉取或解析失败'));
                }
            });
        });
        $("#addSubAct").click(function() {
            $("#grid-subscriptions tfoot button[data-action='add']").click();
        });
        $("#updateAllSubsAct").click(function() {
            var $r = $("#subResult");
            fetchAll('/api/xray/settings/searchSubscriptions').done(function(rows) {
                if (!rows.length) { $r.text("没有订阅。"); return; }
                $r.removeClass("text-success text-danger").text("更新中…（0/" + rows.length + "）");
                var ok = 0, total = 0, anyReloaded = false, anyWarning = '';
                var chain = $.Deferred().resolve();
                $.each(rows, function(i, row) {
                    chain = chain.then(function() {
                        var d = $.Deferred();
                        updateSub(row.uuid, function(data) {
                            if (data['result'] === 'saved') {
                                ok++; total += (data['added'] || 0);
                                if (data['reloaded']) { anyReloaded = true; }
                                if (data['warning']) { anyWarning = data['warning']; }
                            }
                            $r.text("更新中…（" + (i + 1) + "/" + rows.length + "）");
                            d.resolve();
                        });
                        return d.promise();
                    });
                });
                chain.done(function() {
                    var msg = "全部更新完成：" + ok + "/" + rows.length + " 个订阅，共 " + total + " 个节点。";
                    if (anyReloaded) { msg += "命中配置的改动已自动重载生效。"; }
                    else if (anyWarning) { msg += anyWarning; }
                    else { msg += "点底部「应用」生效。"; }
                    $r.addClass("text-success").text(msg);
                    $("#grid-nodes").bootgrid("reload");
                    updateActiveUI();
                    refreshValidationBanner();
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

        // ---- single-node ping (same pingNodes endpoint, one uuid) ----
        $(document).on('click', '.node-ping', function() {
            var $btn = $(this);
            var uuid = $btn.data('uuid');
            var tag = $btn.data('tag') || uuid;
            $btn.prop('disabled', true).text('测试中…');
            ajaxCall(url="/api/xray/settings/pingNodes", sendData={uuids: [uuid]}, callback=function(data, status) {
                $btn.prop('disabled', false).text('连通测试');
                var pings = data['pings'] || {};
                if (pings[uuid] !== undefined) {
                    window.__pings[uuid] = pings[uuid];
                    $("#pingResult").text(tag + '：' + (pings[uuid] >= 0 ? pings[uuid] + ' ms' : '超时') + '。');
                    $("#grid-nodes").bootgrid("reload");
                }
            });
        });

        // ---- single-node egress probe (temp config, trace IP + download speed) ----
        $(document).on('click', '.node-probe', function() {
            var $btn = $(this);
            var uuid = $btn.data('uuid');
            var tag = $btn.data('tag') || uuid;
            var $r = $("#probeResult");
            $btn.prop('disabled', true).text('探测中…');
            ajaxCall(url="/api/xray/settings/probeNode", sendData={uuid: uuid}, callback=function(data, status) {
                $btn.prop('disabled', false).text('出口探测');
                if (data && data['ok']) {
                    var msg = tag + '：出口 ' + data['ip'] + (data['loc'] ? '（' + data['loc'] + '）' : '');
                    msg += (data['speed_mbps'] !== null && data['speed_mbps'] !== undefined) ? '，下载 ' + data['speed_mbps'] + ' Mbps' : '，速度未测到';
                    msg += '。';
                    $r.removeClass("text-danger").addClass("text-muted").text(msg);
                } else {
                    $r.removeClass("text-muted").addClass("text-danger").text(tag + '：探测失败：' + ((data && data['error']) || '未知错误') + '。');
                }
            });
        });

        // ---- outbound test (live config path via socks inbound, 204 + latency) ----
        $("#testOutboundAct").click(function() {
            var $btn = $(this);
            var $r = $("#outboundTestResult");
            $btn.prop("disabled", true);
            $r.removeClass("text-success text-danger").text("测试中…");
            ajaxCall(url="/api/xray/service/testOutbound", sendData={}, callback=function(data, status) {
                $btn.prop("disabled", false);
                if (data && data['ok']) {
                    $r.addClass("text-success").text("通，" + (data['ms'] || 0) + " ms（经当前配置的默认出站）。");
                } else {
                    $r.addClass("text-danger").text("断：" + ((data && data['error']) || '探针失败'));
                }
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
                updateServiceControlUI('xray');
                refreshValidationBanner();
            });
        });

        updateServiceControlUI('xray');

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

<div id="validationBanner" class="alert alert-danger hidden" role="alert" style="white-space: pre-wrap;"></div>
<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
    <li class="active"><a data-toggle="tab" href="#nodes">节点</a></li>
    <li><a data-toggle="tab" href="#subscriptions">订阅</a></li>
    <li><a data-toggle="tab" href="#import">快捷导入</a></li>
</ul>
<div class="tab-content content-box tab-content">
    <div id="nodes" class="tab-pane fade in active">
        <div class="alert alert-info" style="padding: 8px 12px; margin-bottom: 10px;">
            <div class="pull-right">
                <button class="btn btn-default btn-sm" id="testOutboundAct" type="button">测试出站</button>
            </div>
            <div style="line-height: 30px;">
                当前活动节点：<b id="activeNodeTag">未设置</b>
                <span id="outboundTestResult" style="margin-left: 10px;"></span>
            </div>
            <div class="clearfix"></div>
            <small class="text-muted">默认出站为“默认节点”时，未命中规则的流量走活动节点；点节点行里的 ☆ 设为活动，设好后点底部「应用」生效。</small>
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
                    <th data-column-id="ping" data-type="string" data-width="6em" data-sortable="false" data-formatter="pingFmt">连通测试</th>
                    <th data-column-id="probe" data-type="string" data-width="8em" data-sortable="false" data-formatter="probeFmt">出口探测</th>
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
        <div style="margin-top: 10px;">
            <button class="btn btn-default btn-sm" id="pingNodesAct" type="button">全部连通测试</button>
            <span id="pingResult" class="text-muted" style="margin-left: 10px;"></span>
            <span id="probeResult" class="text-muted" style="margin-left: 10px;"></span>
        </div>
    </div>
    <div id="subscriptions" class="tab-pane fade">
        <div class="panel panel-default">
            <div class="panel-heading"><b>订阅管理</b> <span class="text-muted">— 更新会拉取订阅并按指纹同步该订阅的节点（更新已有的、新增没有的、删除订阅里已消失的）；命中活动节点或规则的改动会自动重载生效</span></div>
            <div class="panel-body">
                <table id="grid-subscriptions" class="table table-condensed table-hover table-striped" data-editDialog="DialogSubscription">
                    <thead>
                        <tr>
                            <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">ID</th>
                            <th data-column-id="name" data-type="string">名称</th>
                            <th data-column-id="url" data-type="string">订阅链接</th>
                            <th data-column-id="count" data-type="numeric" data-width="6em" data-sortable="false" data-formatter="subCountFmt">条数</th>
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
                    <button class="btn btn-default btn-sm" id="addSubAct" type="button">添加订阅</button>
                    <button class="btn btn-default btn-sm" id="updateAllSubsAct" type="button">全部更新</button>
                    <span id="subResult" style="margin-left: 10px;"></span>
                </div>
            </div>
        </div>
    </div>
    <div id="import" class="tab-pane fade">
        <div class="panel panel-default">
            <div class="panel-heading"><b>导入节点</b> <span class="text-muted">— 粘贴 vless / vmess / trojan / ss 链接，一行一个；也可以整段粘贴订阅内容（明文或 Base64）</span></div>
            <div class="panel-body">
                <textarea id="importLinks" rows="10" class="form-control" style="width: 100%; font-family: monospace;" placeholder="vless://…&#10;vmess://…"></textarea>
                <div style="margin-top: 10px;">
                    <button class="btn btn-primary btn-sm" id="importNodesAct" type="button">导入</button>
                    <span id="importResult" style="margin-left: 10px;"></span>
                </div>
            </div>
        </div>
    </div>
</div>

<div class="content-box" style="margin-top: 20px; padding: 15px 0;">
    <div class="col-md-12">
        <button class="btn btn-primary" id="reconfigureAct" type="button">
            <b>应用</b> <i id="reconfigureAct_progress"></i>
        </button>
    </div>
    <div class="col-md-12" style="margin-top: 10px;">
        <div id="responseMsg" class="alert hidden" role="alert"></div>
    </div>
</div>

{{ partial("layout_partials/base_dialog",['fields':nodeForm,'id':'DialogNode','label':lang._('编辑节点')])}}
{{ partial("layout_partials/base_dialog",['fields':subscriptionForm,'id':'DialogSubscription','label':lang._('编辑订阅')])}}
