{#
 # Copyright (C) 2026 nxovaeng
 # All rights reserved.
 #}

<script>
    function escHtml(s) {
        return $('<div>').text(s == null ? '' : String(s)).html();
    }

    $(document).ready(function() {
        window.__groups = {};

        var typeBadges = {
            direct: '<span class="label label-success">直连</span>',
            proxy: '<span class="label label-primary">代理</span>',
            block: '<span class="label label-danger">阻止</span>'
        };

        // ---- groups grid ----
        $("#grid-groups").UIBootgrid({
            search: '/api/mosdns/settings/searchGroups',
            get: '/api/mosdns/settings/getGroup/',
            set: '/api/mosdns/settings/setGroup/',
            add: '/api/mosdns/settings/addGroup/',
            del: '/api/mosdns/settings/delGroup/',
            toggle: '/api/mosdns/settings/toggleGroup/',
            formatters: {
                typeFmt: function(column, row) { return typeBadges[row.type] || escHtml(row.type); },
                sourceFmt: function(column, row) {
                    return row.source === 'remote'
                        ? '<span class="label label-info">在线</span>'
                        : '<span class="label label-default">本地</span>';
                },
                urlFmt: function(column, row) {
                    if (row.source !== 'remote' || !row.url) return '<span class="text-muted">—</span>';
                    var u = escHtml(row.url);
                    return '<span title="' + u + '">' + (row.url.length > 42 ? u.substring(0, 42) + '…' : u) + '</span>';
                }
            }
        });

        function fetchAll(url) {
            var d = $.Deferred();
            ajaxCall(url=url, sendData={current: 1, rowCount: -1, searchPhrase: '', sort: {}}, callback=function(data, status) {
                d.resolve(data['rows'] || []);
            });
            return d.promise();
        }

        // ---- merge status / merged files ----
        function refreshFileStats(selectName) {
            ajaxCall(url="/api/mosdns/service/listRules", sendData={}, callback=function(data, status) {
                var byName = {};
                $.each(data['files'] || [], function(i, f) { byName[f['name']] = f; });
                var order = ['custom-direct.txt', 'custom-proxy.txt', 'custom-block.txt'];
                var html = $.map(order, function(n) {
                    var f = byName[n];
                    return n.replace('custom-', '').replace('.txt', '') + ' <b>' + (f ? f['count'] : 0) + '</b>';
                }).join(' · ');
                $("#mergedStats").html(html);
                var $sel = $("#previewFileSelect");
                var cur = selectName || $sel.val();
                $sel.empty();
                $.each(data['files'] || [], function(i, f) {
                    $sel.append($("<option>").val(f['name']).text(f['name'] + "（" + f['count'] + " 条）"));
                });
                if (cur && byName[cur]) $sel.val(cur);
                loadPreview();
            });
        }

        function loadPreview() {
            var name = $("#previewFileSelect").val();
            if (!name) return;
            ajaxCall(url="/api/mosdns/service/getRule/" + name, sendData={}, callback=function(data, status) {
                $("#previewContent").val(data['content'] || '');
            });
        }
        $("#previewFileSelect").change(loadPreview);

        function mergeSummaryText(data) {
            if (!data || data['result'] !== 'ok') return null;
            var f = data['files'] || {};
            var parts = [];
            $.each(['direct', 'proxy', 'block'], function(i, t) {
                if (f[t]) parts.push(t + ' ' + f[t]['count'] + ' 条（' + (f[t]['groups'] || []).length + ' 组）');
            });
            var txt = '已合并：' + parts.join('，') + '。';
            if (data['warnings'] && data['warnings'].length) {
                txt += ' 警告：' + data['warnings'].join('；');
            }
            return txt;
        }

        $("#mergeRulesAct").click(function() {
            var $m = $("#mergeMsg");
            $m.removeClass("text-danger text-success").addClass("text-muted").text("合并中…");
            ajaxCall(url="/api/mosdns/service/mergeRules", sendData={}, callback=function(data, status) {
                var txt = mergeSummaryText(data);
                if (txt) {
                    $m.removeClass("text-muted text-danger").addClass((data['warnings'] || []).length ? "text-danger" : "text-success")
                      .text(txt + ' mosdns 已重启。');
                } else {
                    $m.removeClass("text-muted").addClass("text-danger").text("合并失败：" + (data['output'] || data['error'] || '未知错误'));
                }
                refreshFileStats();
                loadGroupContent();
            });
        });

        // ---- group content editor ----
        function refreshGroupSelect(keep) {
            fetchAll('/api/mosdns/settings/searchGroups').done(function(rows) {
                window.__groups = {};
                var $sel = $("#groupContentSelect").empty();
                $.each(rows, function(i, r) {
                    window.__groups[r.uuid] = r;
                    $sel.append($("<option>").val(r.uuid)
                        .text(r.name + '（' + (r.type || '') + ' / ' + (r.source === 'remote' ? '在线' : '本地') + '）'));
                });
                if (keep && window.__groups[keep]) $sel.val(keep);
                loadGroupContent();
            });
        }

        function fmtTime(ts) {
            if (!ts) return '从未';
            return new Date(ts * 1000).toLocaleString();
        }

        function loadGroupContent() {
            var uuid = $("#groupContentSelect").val();
            var g = window.__groups[uuid];
            if (!g) {
                $("#groupContent").val('');
                $("#groupContentMeta").text('没有规则组，先在上面新建一个。');
                $("#saveGroupContentAct").prop("disabled", true);
                $("#fetchGroupAct").prop("disabled", true);
                return;
            }
            ajaxCall(url="/api/mosdns/service/getGroupContent/" + uuid, sendData={}, callback=function(data, status) {
                if (data['result'] !== 'ok') {
                    $("#groupContentMeta").text('读取失败：' + (data['error'] || ''));
                    return;
                }
                $("#groupContent").val(data['content'] || '');
                var remote = g.source === 'remote';
                $("#groupContent").prop("readonly", remote);
                $("#saveGroupContentAct").prop("disabled", remote);
                $("#fetchGroupAct").prop("disabled", !remote);
                $("#groupContentMeta").text(
                    (remote ? '在线组，内容是上次拉取的缓存（只读）。' : '本地组，可直接编辑。')
                    + ' 共 ' + (data['count'] || 0) + ' 条，上次更新 ' + fmtTime(data['mtime']) + '。'
                    + (data['exists'] ? '' : ' 尚无内容。'));
            });
        }
        $("#groupContentSelect").change(loadGroupContent);

        $("#saveGroupContentAct").click(function() {
            var uuid = $("#groupContentSelect").val();
            if (!uuid) return;
            var $m = $("#groupContentMsg");
            $m.removeClass("text-danger").addClass("text-muted").text("保存中…");
            ajaxCall(url="/api/mosdns/service/setGroupContent/" + uuid, sendData={content: $("#groupContent").val()}, callback=function(data, status) {
                if (data['result'] === 'saved') {
                    var txt = mergeSummaryText(data['merge']);
                    $m.removeClass("text-muted text-danger").addClass("text-success")
                      .text('已保存并合并，mosdns 已重启。' + (txt ? ' ' + txt : ''));
                } else if (data['errors'] && data['errors'].length) {
                    $m.removeClass("text-muted").addClass("text-danger").text('校验失败：' + data['errors'].join('；'));
                } else {
                    $m.removeClass("text-muted").addClass("text-danger").text('保存失败：' + (data['output'] || data['error'] || '未知错误'));
                }
                refreshFileStats();
                loadGroupContent();
            });
        });

        $("#fetchGroupAct").click(function() {
            var uuid = $("#groupContentSelect").val();
            if (!uuid) return;
            var $m = $("#groupContentMsg");
            $m.removeClass("text-danger").addClass("text-muted").text("拉取中…");
            ajaxCall(url="/api/mosdns/service/fetchGroup/" + uuid, sendData={}, callback=function(data, status) {
                if (data['result'] === 'ok') {
                    $m.removeClass("text-muted text-danger").addClass("text-success")
                      .text('已拉取 ' + (data['count'] || 0) + ' 条并合并，mosdns 已重启。');
                } else if (data['errors'] && data['errors'].length) {
                    $m.removeClass("text-muted").addClass("text-danger").text('拉取内容校验失败（保留旧缓存）：' + data['errors'].join('；'));
                } else {
                    $m.removeClass("text-muted").addClass("text-danger").text('拉取失败（保留旧缓存）：' + (data['error'] || '未知错误'));
                }
                refreshFileStats();
                loadGroupContent();
            });
        });

        refreshFileStats('custom-direct.txt');
        refreshGroupSelect();
    });
</script>

<div class="content-box" style="margin-bottom: 15px;">
    <p class="text-muted" style="margin-bottom: 8px;">
        规则组是<b>纯 txt 域名清单</b>（一行一条：裸域名 / domain: / full:，# 开头是注释），带类型、标签、来源标记，是唯一的规则源。
        在线组填一个纯 txt 地址即可（可托管到 Vercel 等静态托管），家里和办公室填同一个地址就能复用同一份规则。
        保存或应用时，启用的组会被合并进 mosdns 的内置文件 custom-direct / custom-proxy / custom-block.txt 并导出共享清单；
        xray 等其他工具读同一份清单和 txt，按各自格式转换使用。关掉的组不参与合并，可临时停用。
    </p>
    <div>
        <button class="btn btn-primary btn-sm" id="mergeRulesAct" type="button">合并并应用</button>
        <span class="text-muted" style="margin-left: 10px;">内置文件当前条数：<span id="mergedStats"></span></span>
    </div>
    <div id="mergeMsg" style="margin-top: 6px;"></div>
</div>

<div class="content-box">
    <h4 style="margin-top: 0;">规则组</h4>
    <table id="grid-groups" class="table table-condensed table-hover table-striped" data-editDialog="DialogGroup">
        <thead>
            <tr>
                <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">ID</th>
                <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">启用</th>
                <th data-column-id="name" data-type="string">名称</th>
                <th data-column-id="type" data-width="7em" data-type="string" data-formatter="typeFmt">类型</th>
                <th data-column-id="tags" data-type="string">标签</th>
                <th data-column-id="source" data-width="7em" data-type="string" data-formatter="sourceFmt">来源</th>
                <th data-column-id="url" data-type="string" data-formatter="urlFmt">在线地址</th>
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
    <p class="text-muted">改完组信息（名称/类型/开关/地址）后，点上方「合并并应用」生效。</p>
</div>

<div class="content-box" style="margin-top: 15px;">
    <h4 style="margin-top: 0;">组内容</h4>
    <div class="form-group">
        <select id="groupContentSelect" class="form-control" style="max-width: 420px;"></select>
    </div>
    <p id="groupContentMeta" class="text-muted"></p>
    <textarea id="groupContent" rows="16" class="form-control" style="font-family: monospace;" placeholder="一行一条，如：&#10;example.com&#10;domain:google.com&#10;full:exact.example.com&#10;# 注释"></textarea>
    <div style="margin-top: 10px;">
        <button class="btn btn-primary btn-sm" id="saveGroupContentAct" type="button">保存内容</button>
        <button class="btn btn-default btn-sm" id="fetchGroupAct" type="button">拉取更新</button>
        <span id="groupContentMsg" style="margin-left: 10px;"></span>
    </div>
    <p class="text-muted" style="margin-top: 6px;">本地组保存内容后自动合并并重启 mosdns；在线组拉取成功后同样自动合并，拉取失败保留旧缓存。</p>
</div>

<div class="content-box" style="margin-top: 15px;">
    <h4 style="margin-top: 0;">合并结果预览</h4>
    <p class="text-muted">custom-*.txt 由规则组合并生成，不要直接编辑（改组即可）；cn.txt / gfw.txt 是权威名单，只读。</p>
    <div class="form-group">
        <select id="previewFileSelect" class="form-control" style="max-width: 300px;"></select>
    </div>
    <textarea id="previewContent" rows="12" class="form-control" style="font-family: monospace;" readonly></textarea>
</div>

{{ partial("layout_partials/base_dialog",['fields':rulegroupForm,'id':'DialogGroup','label':lang._('编辑规则组')])}}
