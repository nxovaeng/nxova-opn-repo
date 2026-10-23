{#
 # Copyright (C) 2026 nxovaeng
 # All rights reserved.
 #}

<script>
    function escHtml(s) {
        return $('<div>').text(s == null ? '' : String(s)).html();
    }

    $(document).ready(function() {
        var typeBadges = {
            direct: '<span class="label label-success">直连</span>',
            proxy: '<span class="label label-primary">代理</span>',
            block: '<span class="label label-danger">阻止</span>'
        };
        function typeFmt(column, row) { return typeBadges[row.type] || escHtml(row.type); }

        // ---- local groups grid (content edited in a modal) ----
        $("#grid-groups-local").UIBootgrid({
            search: '/api/mosdns/settings/searchLocalGroups',
            get: '/api/mosdns/settings/getGroup/',
            set: '/api/mosdns/settings/setGroup/',
            add: '/api/mosdns/settings/addLocalGroup/',
            del: '/api/mosdns/settings/delGroup/',
            toggle: '/api/mosdns/settings/toggleGroup/',
            formatters: {
                typeFmt: typeFmt,
                contentFmt: function(column, row) {
                    return '<button type="button" class="btn btn-xs btn-primary grp-content" data-mode="edit" data-uuid="' + row.uuid + '">'
                         + '<span class="fa fa-pencil"></span> 修改内容</button>';
                }
            }
        });

        // ---- remote groups grid (content fetched from URL, cache viewable) ----
        $("#grid-groups-remote").UIBootgrid({
            search: '/api/mosdns/settings/searchRemoteGroups',
            get: '/api/mosdns/settings/getGroup/',
            set: '/api/mosdns/settings/setGroup/',
            add: '/api/mosdns/settings/addRemoteGroup/',
            del: '/api/mosdns/settings/delGroup/',
            toggle: '/api/mosdns/settings/toggleGroup/',
            formatters: {
                typeFmt: typeFmt,
                urlFmt: function(column, row) {
                    if (!row.url) return '<span class="text-muted">—</span>';
                    var u = escHtml(row.url);
                    return '<span title="' + u + '">' + (row.url.length > 42 ? u.substring(0, 42) + '…' : u) + '</span>';
                },
                opsFmt: function(column, row) {
                    return '<button type="button" class="btn btn-xs btn-default grp-fetch" data-uuid="' + row.uuid + '">'
                         + '<span class="fa fa-refresh"></span> 拉取</button> '
                         + '<button type="button" class="btn btn-xs btn-default grp-content" data-mode="view" data-uuid="' + row.uuid + '">'
                         + '<span class="fa fa-eye"></span> 查看缓存</button>';
                }
            }
        });

        // ---- merged files: stats + preview ----
        function refreshFileStats(selectName) {
            ajaxCall("/api/mosdns/service/listRules", {}, function(data, status) {
                var byName = {};
                $.each(data['files'] || [], function(i, f) { byName[f['name']] = f; });
                var order = ['sync_direct.txt', 'sync_proxy.txt', 'sync_block.txt'];
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
            ajaxCall("/api/mosdns/service/getRule/" + name, {}, function(data, status) {
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
            ajaxCall("/api/mosdns/service/mergeRules", {}, function(data, status) {
                var txt = mergeSummaryText(data);
                if (txt) {
                    $m.removeClass("text-muted text-danger").addClass((data['warnings'] || []).length ? "text-danger" : "text-success")
                      .text(txt + ' mosdns 已重启。');
                } else {
                    $m.removeClass("text-muted").addClass("text-danger").text("合并失败：" + (data['output'] || data['error'] || '未知错误'));
                }
                refreshFileStats();
            });
        });

        // ---- group content modal (local: edit; remote: view cache) ----
        var gcUuid = null;

        function fmtTime(ts) {
            if (!ts) return '从未';
            return new Date(ts * 1000).toLocaleString();
        }

        function openGroupContent(uuid, mode) {
            gcUuid = uuid;
            var edit = (mode === 'edit');
            $("#gcTitle").text(edit ? '修改内容' : '查看缓存');
            $("#gcSave").toggle(edit);
            $("#gcText").prop('readonly', !edit);
            $("#gcMsg").removeClass("text-danger text-success").text('');
            $("#gcMeta").text('加载中…');
            $("#gcText").val('');
            $("#groupContentModal").modal('show');
            ajaxCall("/api/mosdns/settings/getGroup/" + uuid, {}, function(gdata, status) {
                var g = (gdata && gdata['group']) || {};
                $("#gcTitle").text((edit ? '修改内容' : '查看缓存') + ' - ' + (g['name'] || ''));
            });
            ajaxCall("/api/mosdns/service/getGroupContent/" + uuid, {}, function(data, status) {
                if (data['result'] !== 'ok') {
                    $("#gcMeta").text('读取失败：' + (data['error'] || ''));
                    return;
                }
                $("#gcText").val(data['content'] || '');
                $("#gcMeta").text(
                    '共 ' + (data['count'] || 0) + ' 条，上次更新 ' + fmtTime(data['mtime']) + '。'
                    + (data['exists'] ? '' : ' 尚无内容。')
                    + (edit ? '' : ' 在线组内容来自拉取缓存，只读；要更新点行内「拉取」。'));
            });
        }

        $(document).on('click', '.grp-content', function() {
            openGroupContent($(this).data('uuid'), $(this).data('mode'));
        });

        $("#gcSave").click(function() {
            if (!gcUuid) return;
            var $m = $("#gcMsg");
            $m.removeClass("text-danger text-success").addClass("text-muted").text("保存中…");
            ajaxCall("/api/mosdns/service/setGroupContent/" + gcUuid, {content: $("#gcText").val()}, function(data, status) {
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
            });
        });

        // ---- remote fetch (row button) ----
        $(document).on('click', '.grp-fetch', function() {
            var uuid = $(this).data('uuid');
            var $m = $("#remoteMsg");
            $m.removeClass("text-danger text-success").addClass("text-muted").text("拉取中…");
            ajaxCall("/api/mosdns/service/fetchGroup/" + uuid, {}, function(data, status) {
                if (data['result'] === 'ok') {
                    var txt = mergeSummaryText(data['merge']);
                    $m.removeClass("text-muted text-danger").addClass("text-success")
                      .text('已拉取 ' + (data['count'] || 0) + ' 条并合并，mosdns 已重启。' + (txt ? ' ' + txt : ''));
                } else if (data['errors'] && data['errors'].length) {
                    $m.removeClass("text-muted").addClass("text-danger").text('拉取内容校验失败（保留旧缓存）：' + data['errors'].join('；'));
                } else {
                    $m.removeClass("text-muted").addClass("text-danger").text('拉取失败（保留旧缓存）：' + (data['error'] || '未知错误'));
                }
                refreshFileStats();
            });
        });

        refreshFileStats('sync_direct.txt');
    });
</script>

<div class="content-box" style="margin-bottom: 15px;">
    <p class="text-muted" style="margin-bottom: 8px;">
        规则组是<b>纯 txt 域名清单</b>（一行一条：裸域名 / domain: / full:，# 开头是注释），带类型、标签标记，是唯一的规则源。
        本地组在本页维护内容；在线组只填一个纯 txt 地址（可托管到 Vercel 等静态托管），家里和办公室填同一个地址就能复用同一份规则。
        保存或应用时，启用的组会被合并进 mosdns 的 sync_direct / sync_proxy / sync_block.txt 并导出共享清单；
        xray 等其他工具读同一份清单和 txt，按各自格式转换使用。关掉的组不参与合并，可临时停用。
    </p>
    <div>
        <button class="btn btn-primary btn-sm" id="mergeRulesAct" type="button">合并并应用</button>
        <span class="text-muted" style="margin-left: 10px;">内置文件当前条数：<span id="mergedStats"></span></span>
    </div>
    <div id="mergeMsg" style="margin-top: 6px;"></div>
</div>

<div class="content-box">
    <h4 style="margin-top: 0;">本地组</h4>
    <table id="grid-groups-local" class="table table-condensed table-hover table-striped" data-editDialog="DialogLocalGroup">
        <thead>
            <tr>
                <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">ID</th>
                <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">启用</th>
                <th data-column-id="name" data-type="string">名称</th>
                <th data-column-id="type" data-width="7em" data-type="string" data-formatter="typeFmt">类型</th>
                <th data-column-id="tags" data-type="string">标签</th>
                <th data-column-id="content" data-width="9em" data-type="string" data-formatter="contentFmt" data-sortable="false">内容</th>
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
    <p class="text-muted">新建组后点行内「修改内容」填写规则（弹窗编辑，保存后自动合并）；改组信息（名称/类型/开关）后点上方「合并并应用」生效。</p>
</div>

<div class="content-box" style="margin-top: 15px;">
    <h4 style="margin-top: 0;">在线组</h4>
    <table id="grid-groups-remote" class="table table-condensed table-hover table-striped" data-editDialog="DialogRemoteGroup">
        <thead>
            <tr>
                <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">ID</th>
                <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">启用</th>
                <th data-column-id="name" data-type="string">名称</th>
                <th data-column-id="type" data-width="7em" data-type="string" data-formatter="typeFmt">类型</th>
                <th data-column-id="tags" data-type="string">标签</th>
                <th data-column-id="url" data-type="string" data-formatter="urlFmt">在线地址</th>
                <th data-column-id="ops" data-width="12em" data-type="string" data-formatter="opsFmt" data-sortable="false">内容</th>
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
    <div id="remoteMsg" style="margin-top: 6px;"></div>
    <p class="text-muted">新建组填好在线地址后，点行内「拉取」获取内容（成功后自动合并）；「查看缓存」看上次拉取到的内容。拉取失败保留旧缓存。</p>
</div>

<div class="content-box" style="margin-top: 15px;">
    <h4 style="margin-top: 0;">合并结果预览</h4>
    <p class="text-muted">sync_*.txt 由规则组合并生成，不要直接编辑（改组即可）。</p>
    <div class="form-group">
        <select id="previewFileSelect" class="form-control" style="max-width: 300px;"></select>
    </div>
    <textarea id="previewContent" rows="12" class="form-control" style="font-family: monospace;" readonly></textarea>
</div>

<div class="modal fade" id="groupContentModal" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog modal-lg">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
                <h4 class="modal-title" id="gcTitle">修改内容</h4>
            </div>
            <div class="modal-body">
                <p id="gcMeta" class="text-muted"></p>
                <textarea id="gcText" rows="18" class="form-control" style="font-family: monospace;" placeholder="一行一条，如：&#10;example.com&#10;domain:google.com&#10;full:exact.example.com&#10;# 注释"></textarea>
                <div id="gcMsg" style="margin-top: 8px;"></div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-default" data-dismiss="modal">关闭</button>
                <button type="button" class="btn btn-primary" id="gcSave">保存并合并</button>
            </div>
        </div>
    </div>
</div>

{{ partial("layout_partials/base_dialog",['fields':rulegroupLocalForm,'id':'DialogLocalGroup','label':lang._('编辑本地组')])}}
{{ partial("layout_partials/base_dialog",['fields':rulegroupRemoteForm,'id':'DialogRemoteGroup','label':lang._('编辑在线组')])}}
