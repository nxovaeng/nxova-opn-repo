{#
 # Copyright (C) 2026 nxovaeng
 # All rights reserved.
 #}

<style>
    .upstream-editor .upstream-row { display: flex; gap: 6px; margin-bottom: 6px; align-items: center; }
    .upstream-editor .upstream-preset { width: 128px; flex: none; }
    .upstream-editor .upstream-val { flex: 1; }
    .upstream-editor .upstream-invalid { border-color: #a94442 !important; background-color: #f2dede; }
</style>

<script>
    function escHtml(s) {
        return $('<div>').text(s == null ? '' : String(s)).html();
    }

    $(document).ready(function() {
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

        // ---- general settings ----
        mapDataToFormUI({'frm_GeneralSettings': "/api/xray/settings/get"}).done(function() {
            $('.selectpicker').selectpicker('refresh');
            upstreamEditor('xray.general.dns_servers');
            upstreamEditor('xray.general.dns_local_servers');
            upstreamEditor('xray.general.dns_remote_servers');
        });
        $("#saveGeneralAct").click(function() {
            saveFormToEndpoint(url="/api/xray/settings/set", formid='frm_GeneralSettings',
                callback_ok=function() {
                    $("#responseMsg").removeClass("hidden alert-danger alert-info").addClass("alert-success")
                        .html("设置已保存，点底部「应用」生效。");
                });
        });

        // ---- DNS upstream row editor, brought over from os-mosdns ----
        // one upstream per row, joined back into the (hidden)
        // comma-separated model field on every change; model/generator
        // untouched, so the saved value stays comma-separated.
        var UPSTREAM_PRESETS = [
            ['国内常用', [
                ['223.5.5.5', '阿里 223.5.5.5'],
                ['119.29.29.29', '腾讯 119.29.29.29'],
                ['180.76.76.76', '百度 180.76.76.76'],
                ['114.114.114.114', '114DNS 114.114.114.114'],
                ['1.2.4.8', 'CNNIC 1.2.4.8']
            ]],
            ['国外常用', [
                ['1.1.1.1', 'Cloudflare 1.1.1.1'],
                ['8.8.8.8', 'Google 8.8.8.8'],
                ['9.9.9.9', 'Quad9 9.9.9.9'],
                ['208.67.222.222', 'OpenDNS 208.67.222.222']
            ]],
            ['加密 DNS', [
                ['https://dns.alidns.com/dns-query', '阿里 DoH'],
                ['https://doh.pub/dns-query', '腾讯 DoH'],
                ['https://cloudflare-dns.com/dns-query', 'Cloudflare DoH'],
                ['https://dns.google/dns-query', 'Google DoH'],
                ['tls://1.1.1.1', 'Cloudflare DoT'],
                ['tls://8.8.8.8', 'Google DoT']
            ]]
        ];

        function validUpstream(v) {
            var m = v.match(/^(?:(udp|tcp|tls|https|quic):\/\/)?(\[[0-9a-fA-F:]+\]|(?:\d{1,3}\.){3}\d{1,3}|[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*)(?::(\d{1,5}))?(\/\S*)?$/);
            if (!m) return false;
            if (/^(?:\d{1,3}\.){3}\d{1,3}$/.test(m[2])) {
                var bad = false;
                $.each(m[2].split('.'), function(i, o) { if (parseInt(o, 10) > 255) bad = true; });
                if (bad) return false;
            }
            if (m[3] !== undefined && parseInt(m[3], 10) > 65535) return false;
            if (m[4] !== undefined && m[1] !== 'https') return false;
            return true;
        }

        function upstreamEditor(fieldId) {
            var input = document.getElementById(fieldId);
            if (!input || $(input).data('ueditor')) return;
            $(input).data('ueditor', true).hide();
            var $rows = $('<div></div>');
            var $err = $('<div class="text-danger" style="display:none; margin-top:4px;"></div>');
            var $add = $('<button type="button" class="btn btn-xs btn-default"><i class="fa fa-plus"></i> 添加一行</button>');
            $('<div class="upstream-editor"></div>').append($rows, $add, $err).insertAfter($(input));

            function presetSelect() {
                var $sel = $('<select class="form-control upstream-preset"><option value="">常用DNS…</option></select>');
                $.each(UPSTREAM_PRESETS, function(i, grp) {
                    var $g = $('<optgroup>').attr('label', grp[0]);
                    $.each(grp[1], function(j, it) {
                        $g.append($('<option>').attr('value', it[0]).text(it[1]));
                    });
                    $sel.append($g);
                });
                return $sel;
            }
            function sync() {
                var vals = [], invalid = 0;
                $rows.find('.upstream-row').each(function() {
                    var $vi = $(this).find('.upstream-val');
                    var v = $.trim($vi.val());
                    if (v === '') { $vi.removeClass('upstream-invalid'); return; }
                    if (validUpstream(v)) {
                        $vi.removeClass('upstream-invalid');
                        if ($.inArray(v, vals) === -1) vals.push(v);
                    } else {
                        $vi.addClass('upstream-invalid');
                        invalid++;
                    }
                });
                $(input).val(vals.join(','));
                if (invalid > 0) {
                    $err.text('有 ' + invalid + ' 行格式不对：应为 IP、IP:端口，或 tcp:// / tls:// / https:// 地址。修正后才能保存。').show();
                } else {
                    $err.hide();
                }
                // save is gated on ALL editors, not just this one: with
                // three upstream fields, one editor's sync must not
                // re-enable save while another still holds invalid rows.
                $('#saveGeneralAct').prop('disabled',
                    $('.upstream-editor .upstream-invalid').length > 0);
            }
            function addRow(value) {
                var $row = $('<div class="upstream-row"></div>');
                var $sel = presetSelect();
                var $val = $('<input type="text" class="form-control upstream-val" placeholder="如 223.5.5.5 或 https://dns.alidns.com/dns-query">').val(value || '');
                var $del = $('<button type="button" class="btn btn-xs btn-default" title="删除这一行"><i class="fa fa-times"></i></button>');
                $sel.change(function() {
                    if ($sel.val()) { $val.val($sel.val()); $sel.val(''); sync(); }
                });
                $val.on('input change', sync);
                $del.click(function() {
                    $row.remove();
                    if ($rows.find('.upstream-row').length === 0) addRow('');
                    sync();
                });
                $row.append($sel, $val, $del);
                $rows.append($row);
            }
            $add.click(function() {
                addRow('');
                $rows.find('.upstream-row:last .upstream-val').focus();
            });
            var initial = $.map(($(input).val() || '').split(','), function(v) { return $.trim(v); })
                           .filter(function(v) { return v !== ''; });
            if (initial.length === 0) initial = [''];
            $.each(initial, function(i, v) { addRow(v); });
            sync();
        }

        // ---- grids ----
        $("#grid-inbounds").UIBootgrid({
            search: '/api/xray/settings/searchInbounds',
            get: '/api/xray/settings/getInbound/',
            set: '/api/xray/settings/setInbound/',
            add: '/api/xray/settings/addInbound/',
            del: '/api/xray/settings/delInbound/',
            toggle: '/api/xray/settings/toggleInbound/',
            // Built-in rows are display-only: no edit/copy/delete buttons.
            commands: {
                "edit": {
                    filter: function(cell) { return !cell.getData().builtin; }
                },
                "delete": {
                    filter: function(cell) { return !cell.getData().builtin; }
                },
                "copy": {
                    filter: function(cell) { return !cell.getData().builtin; }
                }
            },
            options: {
                formatters: {
                    // Built-in inbounds are always on: static icon, no toggle.
                    rowtoggle: function(column, row) {
                        if (row.builtin) {
                            return '<span class="fa fa-fw fa-check-square-o" title="内置固定入站"></span>';
                        }
                        if (parseInt(row.enabled, 10) === 1) {
                            return '<span style="cursor: pointer;" class="fa fa-fw fa-check-square-o command-toggle bootgrid-tooltip" data-value="1" data-row-id="' + row.uuid + '"></span>';
                        }
                        return '<span style="cursor: pointer;" class="fa fa-fw fa-square-o command-toggle bootgrid-tooltip" data-value="0" data-row-id="' + row.uuid + '"></span>';
                    }
                }
            }
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
        $("#clearLogAct").click(function() {
            ajaxCall(url="/api/xray/service/clearLog", sendData={}, callback=function(data, status) {
                refreshLog();
            });
        });

        // ---- site connectivity cards (live-config path: HEAD via
        // the selected socks inbound, rules first, else default outbound) ----
        function refreshConntestInbounds() {
            var $sel = $("#conntestInbound");
            ajaxCall(url="/api/xray/settings/searchInbounds", sendData={}, callback=function(data, status) {
                var rows = (data && data['rows']) || [];
                var opts = [];
                var seen = {};
                rows.forEach(function(r) {
                    if (r['protocol'] !== 'socks' || String(r['enabled']) !== '1') { return; }
                    if (seen[r['uuid']]) { return; }
                    seen[r['uuid']] = true;
                    var label = r['tag'] + ' (' + r['listen'] + ':' + r['port'] + ')';
                    var dis = !!r['username'];
                    if (dis) { label += '（需认证，暂不支持）'; }
                    opts.push({uuid: r['uuid'], label: label, disabled: dis});
                });
                // tun2socks-in first, the historical default
                opts.sort(function(a, b) {
                    if (a.uuid === 'builtin-tun2socks-in') { return -1; }
                    if (b.uuid === 'builtin-tun2socks-in') { return 1; }
                    return 0;
                });
                if (opts.length === 0) { return; } // keep hardcoded fallback
                $sel.empty();
                opts.forEach(function(o) {
                    var $o = $("<option>").val(o.uuid).text(o.label);
                    if (o.disabled) { $o.prop('disabled', true); }
                    $sel.append($o);
                });
            });
        }
        refreshConntestInbounds();
        $(document).on('click', '.site-test-card', function() {
            var $card = $(this);
            if ($card.data('testing')) { return; }
            var $st = $card.find('.site-test-status');
            $card.data('testing', true);
            $st.removeClass('text-success text-danger').addClass('text-muted').text('检测中…');
            ajaxCall(url="/api/xray/service/testOutbound", sendData={site: $card.data('site'), inbound: $("#conntestInbound").val() || 'builtin-tun2socks-in'}, callback=function(data, status) {
                $card.data('testing', false);
                if (data && data['ok']) {
                    $st.removeClass('text-muted text-danger').addClass('text-success').text('通，' + (data['ms'] || 0) + ' ms');
                } else {
                    $st.removeClass('text-muted text-success').addClass('text-danger').text('断：' + ((data && data['error']) || '检测失败'));
                }
            });
        });

        updateServiceControlUI('xray');
    });
</script>

<div id="validationBanner" class="alert alert-danger hidden" role="alert" style="white-space: pre-wrap;"></div>
<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
    <li class="active"><a data-toggle="tab" href="#inbounds">入站</a></li>
    <li><a data-toggle="tab" href="#settings">设置</a></li>
    <li><a data-toggle="tab" href="#logs">日志</a></li>
    <li><a data-toggle="tab" href="#conntest">连接检测</a></li>
</ul>
<div class="tab-content content-box tab-content">
    <div id="inbounds" class="tab-pane fade in active">
        <p class="text-muted">内置固定入站：tun2socks-in（127.0.0.1:10808，给 tun2socks 用）、mosdns-in（127.0.0.1:10853）。下面可加自定义入站，如给局域网开一个带认证的 socks。</p>
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
                    <td style="padding-top: 10px;"><button class="btn btn-primary" id="saveGeneralAct" type="button"><b>保存</b></button></td>
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
        <button class="btn btn-default btn-sm" id="clearLogAct" type="button">清空日志</button>
        <pre id="xrayLog" style="margin-top:10px; max-height:500px; overflow:auto; background:#000; color:#0f0;"></pre>
    </div>
    <div id="conntest" class="tab-pane fade">
        <p class="text-muted">经所选 socks 入口 + 当前 live 配置出站检测（命中规则走规则出站，否则走默认出站）；点卡片检测。</p>
        <div class="row" style="margin-bottom: 10px;">
            <div class="col-md-4">
                <label for="conntestInbound">SOCKS 入口</label>
                <select id="conntestInbound" class="form-control">
                    <option value="builtin-tun2socks-in">tun2socks-in (127.0.0.1:10808)</option>
                </select>
                <p class="text-muted">只列出已启用的 socks 入站；mosdns-in/api 不是 socks，不可选；需认证的入站暂不支持探针。</p>
            </div>
        </div>
        <div class="row">
            <div class="col-md-4">
                <div class="panel panel-default site-test-card" data-site="google" style="cursor: pointer;">
                    <div class="panel-body" style="padding: 10px 15px;">
                        <img src="https://www.google.com/favicon.ico" style="width: 32px; height: 32px; float: left; margin-right: 12px;" onerror="this.style.display='none'">
                        <div><b>谷歌连接</b></div>
                        <div class="site-test-status text-muted">点我检测</div>
                    </div>
                </div>
            </div>
            <div class="col-md-4">
                <div class="panel panel-default site-test-card" data-site="github" style="cursor: pointer;">
                    <div class="panel-body" style="padding: 10px 15px;">
                        <img src="https://github.com/favicon.ico" style="width: 32px; height: 32px; float: left; margin-right: 12px;" onerror="this.style.display='none'">
                        <div><b>GitHub连接</b></div>
                        <div class="site-test-status text-muted">点我检测</div>
                    </div>
                </div>
            </div>
            <div class="col-md-4">
                <div class="panel panel-default site-test-card" data-site="youtube" style="cursor: pointer;">
                    <div class="panel-body" style="padding: 10px 15px;">
                        <img src="https://www.youtube.com/favicon.ico" style="width: 32px; height: 32px; float: left; margin-right: 12px;" onerror="this.style.display='none'">
                        <div><b>YouTube连接</b></div>
                        <div class="site-test-status text-muted">点我检测</div>
                    </div>
                </div>
            </div>
        </div>
        <div class="row">
            <div class="col-md-4">
                <div class="panel panel-default site-test-card" data-site="aliyun" style="cursor: pointer;">
                    <div class="panel-body" style="padding: 10px 15px;">
                        <img src="https://www.aliyun.com/favicon.ico" style="width: 32px; height: 32px; float: left; margin-right: 12px;" onerror="this.style.display='none'">
                        <div><b>阿里连接</b></div>
                        <div class="site-test-status text-muted">点我检测</div>
                    </div>
                </div>
            </div>
            <div class="col-md-4">
                <div class="panel panel-default site-test-card" data-site="qq" style="cursor: pointer;">
                    <div class="panel-body" style="padding: 10px 15px;">
                        <img src="https://www.qq.com/favicon.ico" style="width: 32px; height: 32px; float: left; margin-right: 12px;" onerror="this.style.display='none'">
                        <div><b>腾讯连接</b></div>
                        <div class="site-test-status text-muted">点我检测</div>
                    </div>
                </div>
            </div>
            <div class="col-md-4">
                <div class="panel panel-default site-test-card" data-site="youku" style="cursor: pointer;">
                    <div class="panel-body" style="padding: 10px 15px;">
                        <img src="https://www.youku.com/favicon.ico" style="width: 32px; height: 32px; float: left; margin-right: 12px;" onerror="this.style.display='none'">
                        <div><b>优酷连接</b></div>
                        <div class="site-test-status text-muted">点我检测</div>
                    </div>
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

{{ partial("layout_partials/base_dialog",['fields':inboundForm,'id':'DialogInbound','label':lang._('编辑入站')])}}
