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

        // Flush button sits right of the 启动时清空表 (flush_tables) input:
        // wrap the input in a flex row, append the button, a hint and the
        // result line inside the same form cell.
        var $ft = $('input[id$=".flush_tables"]').first();
        if ($ft.length) {
            $ft.wrap('<div style="display:flex; gap:6px; align-items:center;"></div>');
            $ft.css('flex', '1');
            $ft.after('<button type="button" class="btn btn-warning btn-sm" id="flushAliasAct" style="flex:none;"><b>清空别名表</b></button>');
            $ft.closest('td').append('<div class="text-muted" style="margin-top:4px;">立即清空目标别名表及 pf-aliasd 的 TTL 记录，改了分流规则想马上生效时用；新的解析会重新填充。</div><div id="flushMsg" style="margin-top:2px;"></div>');
        }

        $("#flushAliasAct").click(function() {
            stdDialogConfirm('清空别名表',
                '确定要立即清空别名表及 pf-aliasd 里的 TTL 记录吗？新的解析会重新填充。',
                '清空', '取消', function() {
                var $m = $("#flushMsg");
                $m.removeClass("text-danger text-success").addClass("text-muted").text('清空中…');
                ajaxCall(url="/api/mosdns/service/pfaliasdFlush", sendData={}, callback=function(data, status) {
                    if (data['result'] === 'ok') {
                        var parts = $.map(data['tables'] || [], function(t) {
                            var n = (t['before'] === null || t['before'] === undefined) ? '?' : t['before'];
                            var note = t['daemon'] === 'ok' ? '' : '（守护未响应，仅用 pfctl 清了表）';
                            return t['table'] + '：清掉 ' + n + ' 条' + note;
                        });
                        $m.removeClass("text-muted text-danger").addClass("text-success").text(parts.join('; '));
                    } else {
                        $m.removeClass("text-muted").addClass("text-danger")
                          .text('清空失败：' + (data['error'] || data['output'] || '?'));
                    }
                });
            });
        });
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
