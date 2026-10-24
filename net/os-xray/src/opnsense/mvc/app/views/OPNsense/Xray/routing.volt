{#
 # Copyright (C) 2026 nxovaeng
 # All rights reserved.
 #}

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

        // ---- formatters ----
        var typeNames = {domain: '域名', ip: 'IP', source: '来源', port: '端口'};

        // ---- grids ----
        $("#grid-rules").UIBootgrid({
            search: '/api/xray/settings/searchRules',
            get: '/api/xray/settings/getRule/',
            set: '/api/xray/settings/setRule/',
            add: '/api/xray/settings/addRule/',
            del: '/api/xray/settings/delRule/',
            toggle: '/api/xray/settings/toggleRule/',
            options: {
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
            }        });

        // ---- helpers ----
        function fetchAll(url) {
            var d = $.Deferred();
            ajaxCall(url=url, sendData={current: 1, rowCount: -1, searchPhrase: '', sort: {}}, callback=function(data, status) {
                d.resolve(data['rows'] || []);
            });
            return d.promise();
        }

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
        $("#addTemplateSocial").click(function() {
            addTemplateRules([{type: 'domain', values: 'x.com,twitter.com,telegram.org,t.me,discord.com,discord.gg,discordapp.com,instagram.com,cdninstagram.com,facebook.com,fb.com,fbcdn.net', outbound_tag: ''}]);
        });
        $("#addTemplateDev").click(function() {
            addTemplateRules([{type: 'domain', values: 'github.com,githubusercontent.com,gitlab.com,stackoverflow.com,stackexchange.com,docker.com,docker.io,hub.docker.com,npmjs.com,pypi.org,files.pythonhosted.org', outbound_tag: ''}]);
        });
        $("#addTemplateGame").click(function() {
            addTemplateRules([{type: 'domain', values: 'steampowered.com,steamcommunity.com,steamstatic.com,epicgames.com,epicgames.dev,battle.net,blizzard.com', outbound_tag: ''}]);
        });
        $("#addTemplateMediaPlus").click(function() {
            addTemplateRules([{type: 'domain', values: 'twitch.tv,ttvnw.net,tiktok.com,tiktokcdn.com', outbound_tag: ''}]);
        });

        // ---- rule dialog outbound: linked dropdown (live node tags) ----
        // The model field stays a TextField (an OptionField cannot list
        // nodes dynamically), so the dialog swaps the text input for a
        // <select> on open, fed by the current node list. The hidden
        // input keeps its name and is what gets submitted, so save
        // behavior is unchanged; a fetch failure just leaves the
        // plain text input in place.
        function ruleOutboundField() {
            return $('#DialogRule').find('input,select,textarea').filter(function() {
                return this.id && (this.id === 'outbound_tag' || this.id.endsWith('.outbound_tag'));
            });
        }
        function buildOutboundSelect() {
            var $input = ruleOutboundField();
            if (!$input.length) return;
            var cur = $input.val() || '';
            var $sel = $('#ruleOutboundSelect');
            if (!$sel.length) {
                $sel = $('<select class="form-control" id="ruleOutboundSelect"></select>');
                $input.hide().after($sel);
                $sel.on('change', function() { $input.val($sel.val()); });
            }
            $sel.empty();
            $sel.append($('<option>').val('').text('默认节点'));
            $sel.append($('<option>').val('direct').text('直连'));
            $sel.append($('<option>').val('block').text('拦截'));
            fetchAll('/api/xray/settings/searchNodes').done(function(rows) {
                $.each(rows, function(i, r) {
                    if (r.tag) $sel.append($('<option>').val(r.tag).text(r.tag));
                });
                // stale tag (node renamed/deleted since the rule was saved): keep it selectable so editing doesn't silently drop it
                if (cur && $sel.find('option').filter(function() { return $(this).val() === cur; }).length === 0) {
                    $sel.append($('<option>').val(cur).text(cur + '（节点已不存在）'));
                }
                $sel.val(cur);
            });
        }
        $(document).on('shown.bs.modal', '#DialogRule', function() { setTimeout(buildOutboundSelect, 60); });
    });
</script>

<div id="validationBanner" class="alert alert-danger hidden" role="alert" style="white-space: pre-wrap;"></div>
<div class="content-box">
    <p>
        <button class="btn btn-default btn-xs" id="addTemplateAI" type="button">＋ AI 服务走代理</button>
        <button class="btn btn-default btn-xs" id="addTemplateMedia" type="button">＋ 流媒体走代理</button>
        <button class="btn btn-default btn-xs" id="addTemplateMediaPlus" type="button">＋ 流媒体补充（Twitch / TikTok）</button>
        <button class="btn btn-default btn-xs" id="addTemplateSocial" type="button">＋ 社交走代理</button>
        <button class="btn btn-default btn-xs" id="addTemplateDev" type="button">＋ 开发者走代理</button>
        <button class="btn btn-default btn-xs" id="addTemplateGame" type="button">＋ 游戏走代理</button>
        <button class="btn btn-default btn-xs" id="addTemplateCN" type="button">＋ 国内直连（geosite/geoip）</button>
        <button class="btn btn-default btn-xs" id="addTemplateAds" type="button">＋ 广告拦截</button>
    </p>
    <p class="text-muted">规则按「顺序」值自小到大匹配，命中即止；都没命中走活动节点。系统规则（DNS、53 端口、私网直连）永远排在最前。出站是联动下拉框：默认节点、直连、拦截，或当前某个节点的标签（节点增删后重新打开对话框即刷新）。设置里开启「共享规则组」后，MosDNS「规则」页的规则组会在应用时自动转换并排在本表规则之后（阻止 &gt; 直连 &gt; 代理）。</p>
    <table id="grid-rules" class="table table-condensed table-hover table-striped" data-editDialog="DialogRule">
        <thead>
            <tr>
                <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">ID</th>
                <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">启用</th>
                <th data-column-id="type" data-type="string" data-width="6em" data-formatter="typeFmt">类型</th>
                <th data-column-id="order" data-type="numeric" data-width="5em">顺序</th>
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

<div class="content-box" style="margin-top: 20px;">
    <div class="col-md-12">
        <button class="btn btn-primary" id="reconfigureAct" type="button">
            <b>应用</b> <i id="reconfigureAct_progress"></i>
        </button>
    </div>
    <div class="col-md-12" style="margin-top: 10px;">
        <div id="responseMsg" class="alert hidden" role="alert"></div>
    </div>
</div>

{{ partial("layout_partials/base_dialog",['fields':ruleForm,'id':'DialogRule','label':lang._('编辑规则')])}}
