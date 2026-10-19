{#
 # Copyright (C) 2026 nxovaeng
 # All rights reserved.
 #}

<script>
    $(document).ready(function() {
        function loadRuleList() {
            ajaxCall(url="/api/mosdns/service/listRules", sendData={}, callback=function(data, status) {
                var sel = $("#ruleFileSelect").empty();
                $.each(data['files'] || [], function(i, f) {
                    sel.append($("<option>").val(f['name']).text(f['name'] + " (" + f['count'] + ")" + (f['editable'] ? "" : " [read-only]")));
                });
                loadRuleContent();
            });
        }
        function loadRuleContent() {
            var name = $("#ruleFileSelect").val();
            if (!name) return;
            ajaxCall(url="/api/mosdns/service/getRule/" + name, sendData={}, callback=function(data, status) {
                $("#ruleFileContent").val(data['content'] || '');
                var editable = !/\[read-only\]/.test($("#ruleFileSelect option:selected").text());
                $("#ruleFileContent").prop("disabled", !editable);
                $("#saveRuleFileAct").prop("disabled", !editable);
            });
        }
        $("#ruleFileSelect").change(loadRuleContent);
        $("#saveRuleFileAct").click(function() {
            var name = $("#ruleFileSelect").val();
            $("#ruleFileMsg").removeClass("text-danger").addClass("text-muted").text("{{ lang._('Saving...') }}");
            ajaxCall(url="/api/mosdns/service/setRule/" + name, sendData={content: $("#ruleFileContent").val()}, callback=function(data, status) {
                if (data['result'] == 'saved') {
                    $("#ruleFileMsg").removeClass("text-danger").addClass("text-muted").text("{{ lang._('Saved, mosdns restarted.') }}");
                } else {
                    var msg = "{{ lang._('Validation failed:') }} ";
                    if (data['errors'] && data['errors'].length) {
                        msg += data['errors'].join("; ");
                    } else {
                        msg += (data['output'] || 'unknown error');
                    }
                    $("#ruleFileMsg").removeClass("text-muted").addClass("text-danger").text(msg);
                }
                loadRuleList();
            });
        });
        loadRuleList();
    });
</script>

<div class="content-box">
    <p class="text-muted">{{ lang._('Edit custom rule lists. Authority lists (cn.txt, gfw.txt) are read-only. Saving restarts mosdns to reload the lists.') }}</p>
    <div class="form-group">
        <select id="ruleFileSelect" class="form-control" style="max-width:300px;"></select>
    </div>
    <textarea id="ruleFileContent" rows="20" class="form-control" style="font-family:monospace;"></textarea>
    <div style="margin-top:10px;">
        <button class="btn btn-primary btn-sm" id="saveRuleFileAct" type="button">{{ lang._('Save list') }}</button>
        <span id="ruleFileMsg" class="text-muted" style="margin-left:10px;"></span>
    </div>
</div>
