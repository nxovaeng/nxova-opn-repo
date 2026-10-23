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
    $(document).ready(function() {
        var data_get_map = {
            'frm_GeneralSettings': "/api/mosdns/settings/get",
            'frm_ForwardSettings': "/api/mosdns/settings/get",
            'frm_PfaliasSettings': "/api/mosdns/settings/get"
        };
        mapDataToFormUI(data_get_map).done(function(data) {
            $('.selectpicker').selectpicker('refresh');
            upstreamEditor('mosdns.forward.remote_upstreams');
            upstreamEditor('mosdns.forward.local_upstreams');
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
                updateServiceControlUI('mosdns');
            });
        });

        updateServiceControlUI('mosdns');

        // ---- DNS upstream row editors: one upstream per row, joined back
        // into the (hidden) comma-separated model field on every change ----
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
                    $('#saveForwardAct').prop('disabled', true);
                } else {
                    $err.hide();
                    $('#saveForwardAct').prop('disabled', false);
                }
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
    });
</script>

<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
    <li class="active"><a data-toggle="tab" href="#general">通用</a></li>
    <li><a data-toggle="tab" href="#forward">转发</a></li>
    <li><a data-toggle="tab" href="#pfalias">PF 表同步</a></li>
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
</div>

<div class="content-box" style="margin-top: 20px;">
    <div class="col-md-12">
        <button class="btn btn-primary" id="reconfigureAct" type="button">
            <b>{{ lang._('Apply') }}</b> <i id="reconfigureAct_progress"></i>
        </button>
    </div>
    <div class="col-md-12" style="margin-top: 10px;">
        <div id="responseMsg" class="alert hidden" role="alert"></div>
    </div>
</div>
