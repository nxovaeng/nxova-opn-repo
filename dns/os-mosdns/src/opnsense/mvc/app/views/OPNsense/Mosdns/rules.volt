{#
 # Copyright (C) 2026 nxovaeng
 # All rights reserved.
 #}

<script>
    function escHtml(s) {
        return $('<div>').text(s == null ? '' : String(s)).html();
    }

    function cap(s) { return s.charAt(0).toUpperCase() + s.slice(1); }

    /* Preset online lists (Loyalsoldier/v2ray-rules-dat, release branch),
       per category; each entry: [display name, suggested group name, file] */
    var PRESET_DEFS = {
        direct: [
            ['直连域名 direct-list', 'direct-list', 'direct-list.txt'],
            ['中国域名 china-list', 'china-list', 'china-list.txt'],
            ['Apple 中国 apple-cn', 'apple-cn', 'apple-cn.txt'],
            ['Google 中国 google-cn', 'google-cn', 'google-cn.txt']
        ],
        proxy: [
            ['代理域名 proxy-list', 'proxy-list', 'proxy-list.txt'],
            ['GFW 列表 gfw', 'gfw', 'gfw.txt']
        ],
        block: [
            ['广告拒绝 reject-list', 'reject-list', 'reject-list.txt'],
            ['Win 隐私跟踪 win-spy', 'win-spy', 'win-spy.txt'],
            ['Win 系统更新 win-update', 'win-update', 'win-update.txt'],
            ['Win 附加跟踪 win-extra', 'win-extra', 'win-extra.txt']
        ]
    };
    function presetOptions(type) {
        var out = [];
        $.each(PRESET_DEFS[type] || [], function(i, d) {
            out.push({label: d[0] + '（GitHub）', name: d[1],
                      url: 'https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/' + d[2]});
            out.push({label: d[0] + '（jsdelivr）', name: d[1],
                      url: 'https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/' + d[2]});
        });
        return out;
    }

    $(document).ready(function() {
        function urlFmt(column, row) {
            if (!row.url) return '<span class="text-muted">—</span>';
            var u = escHtml(row.url);
            return '<span title="' + u + '">' + (row.url.length > 42 ? u.substring(0, 42) + '…' : u) + '</span>';
        }
        function contentFmt(column, row) {
            return '<button type="button" class="btn btn-xs btn-primary grp-content" data-mode="edit" data-uuid="' + row.uuid + '">'
                 + '<span class="fa fa-pencil"></span> 修改内容</button>';
        }
        function opsFmt(column, row) {
            return '<button type="button" class="btn btn-xs btn-default grp-fetch" data-uuid="' + row.uuid + '">'
                 + '<span class="fa fa-refresh"></span> 拉取</button> '
                 + '<button type="button" class="btn btn-xs btn-default grp-content" data-mode="view" data-uuid="' + row.uuid + '">'
                 + '<span class="fa fa-eye"></span> 查看缓存</button>';
        }

        // ---- six grids: per type, remote (online) on top, local (custom) below ----
        $.each(['direct', 'proxy', 'block'], function(i, t) {
            $("#grid-remote-" + t).UIBootgrid({
                search: '/api/mosdns/settings/searchRemote' + cap(t) + 'Groups',
                get: '/api/mosdns/settings/getGroup/',
                set: '/api/mosdns/settings/setGroup/',
                add: '/api/mosdns/settings/addRemote' + cap(t) + 'Group/',
                del: '/api/mosdns/settings/delGroup/',
                toggle: '/api/mosdns/settings/toggleGroup/',
                formatters: { urlFmt: urlFmt, opsFmt: opsFmt }
            });
            $("#grid-local-" + t).UIBootgrid({
                search: '/api/mosdns/settings/searchLocal' + cap(t) + 'Groups',
                get: '/api/mosdns/settings/getGroup/',
                set: '/api/mosdns/settings/setGroup/',
                add: '/api/mosdns/settings/addLocal' + cap(t) + 'Group/',
                del: '/api/mosdns/settings/delGroup/',
                toggle: '/api/mosdns/settings/toggleGroup/',
                formatters: { contentFmt: contentFmt }
            });
        });

        $('a[data-toggle="tab"]').on('shown.bs.tab', function() {
            $(window).trigger('resize');
        });

        // ---- preset dropdown inside each remote dialog (fills the URL field) ----
        $.each({Direct: 'direct', Proxy: 'proxy', Block: 'block'}, function(capT, t) {
            var $dlg = $('#DialogRemote' + capT);
            var $url = $dlg.find('[id$=".url"]');
            if (!$dlg.length || !$url.length) return;
            var $sel = $('<select class="form-control grp-preset" style="margin-bottom: 6px;">'
                       + '<option value="">— 选择预设清单（自动填入地址）—</option></select>');
            $.each(presetOptions(t), function(i, p) {
                $sel.append($('<option>').val(p.url).text(p.label).attr('data-gname', p.name));
            });
            $sel.on('change', function() {
                var v = $(this).val();
                if (!v) return;
                $url.val(v).trigger('change');
                var $nm = $dlg.find('[id$=".name"]');
                if ($nm.length && !$nm.val()) {
                    $nm.val($(this).find(':selected').data('gname'));
                }
                $(this).val('');
            });
            $url.before($sel);
        });

        // ---- merged files: stats + preview ----
        function refreshFileStats(selectName) {
            ajaxCall("/api/mosdns/service/listRules", {}, function(data, status) {
                var byName = {};
                $.each(data['files'] || [], function(i, f) { byName[f['name']] = f; });
                var order = ['custom_direct.txt', 'custom_proxy.txt', 'custom_block.txt', 'sync_direct.txt', 'sync_proxy.txt', 'sync_block.txt'];
                var html = $.map(order, function(n) {
                    var f = byName[n];
                    return n.replace('.txt', '') + ' <b>' + (f ? f['count'] : 0) + '</b>';
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
            $.each(['custom_direct', 'custom_proxy', 'custom_block', 'sync_direct', 'sync_proxy', 'sync_block'], function(i, t) {
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
                var nm = g['name'];
                if (nm && typeof nm === 'object') nm = '';
                $("#gcTitle").text((edit ? '修改内容' : '查看缓存') + (nm ? ' - ' + nm : ''));
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
                    var droppedTxt = ((data['dropped'] || 0) > 0 ? '（已移除 ' + data['dropped'] + ' 条不支持的行' : '')
                                     + ((data['converted'] || 0) > 0 ? (droppedTxt === '' ? '（' : '，') + '转换 ' + data['converted'] + ' 条通配符' : '')
                                     + (((data['dropped'] || 0) > 0 || (data['converted'] || 0) > 0) ? '）' : '');
                    $m.removeClass("text-muted text-danger").addClass("text-success")
                      .text('已拉取 ' + (data['count'] || 0) + ' 条并合并' + droppedTxt + '，mosdns 已重启。' + (txt ? ' ' + txt : ''));
                } else if (data['errors'] && data['errors'].length) {
                    $m.removeClass("text-muted").addClass("text-danger").text('拉取内容校验失败（保留旧缓存）：' + data['errors'].join('；'));
                } else {
                    $m.removeClass("text-muted").addClass("text-danger").text('拉取失败（保留旧缓存）：' + (data['error'] || '未知错误'));
                }
                refreshFileStats();
            });
        });

        refreshFileStats('custom_direct.txt');
    });
</script>

<p class="text-muted" style="margin-bottom: 10px;">
    规则组只做 mosdns 的粗粒度分流：哪些域名<b>直连</b>、哪些走<b>代理</b>、哪些<b>阻止</b>，按类别分开管理。
    每类里<b>在线组</b>在上（填一个纯 txt 地址，或从预设清单里选；拉取后缓存到本地）、<b>自定义组</b>在下（内容在本页弹窗里维护）。
    规则一行一条：裸域名（后缀匹配）/ domain: / full: / regexp:，# 开头是注释；单个顶级域名（如 cn）不支持。在线列表同步时会清洗：通配符 *.x 转 domain:x，其余不支持的行（含顶级域名行）直接移除并计数。
    改组信息（名称/标签/开关）后点页面下方「合并并应用」生效；关掉的组不参与合并。
</p>

<ul class="nav nav-tabs" data-tabs="tabs" id="ruletabs">
    <li class="active"><a data-toggle="tab" href="#tab-direct">直连</a></li>
    <li><a data-toggle="tab" href="#tab-proxy">代理</a></li>
    <li><a data-toggle="tab" href="#tab-block">阻止</a></li>
</ul>
<div class="tab-content content-box tab-content" style="padding-top: 12px;">
    <div id="tab-direct" class="tab-pane fade in active">
        <h4 style="margin-top: 0;">在线组（直连）</h4>
        <table id="grid-remote-direct" class="table table-condensed table-hover table-striped" data-editDialog="DialogRemoteDirect">
            <thead>
                <tr>
                    <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">ID</th>
                    <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">启用</th>
                    <th data-column-id="name" data-type="string">名称</th>
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
        <p class="text-muted">新建组时可从预设清单下拉选地址；建好后点行内「拉取」获取内容（成功自动合并），「查看缓存」看上次拉到的内容。拉取失败保留旧缓存。</p>

        <h4 style="margin-top: 18px;">自定义组（直连）</h4>
        <table id="grid-local-direct" class="table table-condensed table-hover table-striped" data-editDialog="DialogLocalDirect">
            <thead>
                <tr>
                    <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">ID</th>
                    <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">启用</th>
                    <th data-column-id="name" data-type="string">名称</th>
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
        <p class="text-muted">新建组后点行内「修改内容」填写规则（弹窗编辑，保存后自动合并）。</p>
    </div>
    <div id="tab-proxy" class="tab-pane fade">
        <h4 style="margin-top: 0;">在线组（代理）</h4>
        <table id="grid-remote-proxy" class="table table-condensed table-hover table-striped" data-editDialog="DialogRemoteProxy">
            <thead>
                <tr>
                    <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">ID</th>
                    <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">启用</th>
                    <th data-column-id="name" data-type="string">名称</th>
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
        <p class="text-muted">新建组时可从预设清单下拉选地址；建好后点行内「拉取」获取内容（成功自动合并），「查看缓存」看上次拉到的内容。拉取失败保留旧缓存。</p>

        <h4 style="margin-top: 18px;">自定义组（代理）</h4>
        <table id="grid-local-proxy" class="table table-condensed table-hover table-striped" data-editDialog="DialogLocalProxy">
            <thead>
                <tr>
                    <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">ID</th>
                    <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">启用</th>
                    <th data-column-id="name" data-type="string">名称</th>
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
        <p class="text-muted">新建组后点行内「修改内容」填写规则（弹窗编辑，保存后自动合并）。</p>
    </div>
    <div id="tab-block" class="tab-pane fade">
        <h4 style="margin-top: 0;">在线组（阻止）</h4>
        <table id="grid-remote-block" class="table table-condensed table-hover table-striped" data-editDialog="DialogRemoteBlock">
            <thead>
                <tr>
                    <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">ID</th>
                    <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">启用</th>
                    <th data-column-id="name" data-type="string">名称</th>
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
        <p class="text-muted">新建组时可从预设清单下拉选地址；建好后点行内「拉取」获取内容（成功自动合并），「查看缓存」看上次拉到的内容。拉取失败保留旧缓存。</p>

        <h4 style="margin-top: 18px;">自定义组（阻止）</h4>
        <table id="grid-local-block" class="table table-condensed table-hover table-striped" data-editDialog="DialogLocalBlock">
            <thead>
                <tr>
                    <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">ID</th>
                    <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">启用</th>
                    <th data-column-id="name" data-type="string">名称</th>
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
        <p class="text-muted">新建组后点行内「修改内容」填写规则（弹窗编辑，保存后自动合并）。</p>
    </div>
</div>
<div id="remoteMsg" style="margin-top: 6px;"></div>

<div class="content-box" style="margin-top: 15px;">
    <h4 style="margin-top: 0;">合并并应用</h4>
    <div>
        <button class="btn btn-primary btn-sm" id="mergeRulesAct" type="button">合并并应用</button>
        <span class="text-muted" style="margin-left: 10px;">合并产物当前条数：<span id="mergedStats"></span></span>
    </div>
    <div id="mergeMsg" style="margin-top: 6px;"></div>
    <div style="margin-top: 12px;">
        <div class="form-group">
            <select id="previewFileSelect" class="form-control" style="max-width: 300px;"></select>
        </div>
        <textarea id="previewContent" rows="12" class="form-control" style="font-family: monospace;" readonly></textarea>
        <p class="text-muted" style="margin-top: 6px;">sync_*.txt 由规则组合并生成，不要直接编辑（改组即可）。</p>
    </div>
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

{{ partial("layout_partials/base_dialog",['fields':rulegroupLocalForm,'id':'DialogLocalDirect','label':lang._('编辑直连自定义组')])}}
{{ partial("layout_partials/base_dialog",['fields':rulegroupRemoteForm,'id':'DialogRemoteDirect','label':lang._('编辑直连在线组')])}}
{{ partial("layout_partials/base_dialog",['fields':rulegroupLocalForm,'id':'DialogLocalProxy','label':lang._('编辑代理自定义组')])}}
{{ partial("layout_partials/base_dialog",['fields':rulegroupRemoteForm,'id':'DialogRemoteProxy','label':lang._('编辑代理在线组')])}}
{{ partial("layout_partials/base_dialog",['fields':rulegroupLocalForm,'id':'DialogLocalBlock','label':lang._('编辑阻止自定义组')])}}
{{ partial("layout_partials/base_dialog",['fields':rulegroupRemoteForm,'id':'DialogRemoteBlock','label':lang._('编辑阻止在线组')])}}
