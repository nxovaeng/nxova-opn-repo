{#
 # Copyright (C) 2026 nxovaeng
 # All rights reserved.
 #}

<script>
    $(document).ready(function() {
        $("#testDomainAct").click(function() {
            var domain = $("#testDomain").val().trim();
            if (!domain) return;
            ajaxCall(url="/api/mosdns/service/testDomain", sendData={domain: domain}, callback=function(data, status) {
                if (data['result'] != 'ok') {
                    $("#testResult").html('<div class="alert alert-danger">' + (data['error'] || 'failed') + '</div>');
                    return;
                }
                var badge = data['action'] == 'proxy' ? 'label-warning' : (data['action'] == 'block' ? 'label-danger' : 'label-success');
                var html = '<h4><span class="label ' + badge + '">' + data['action'] + '</span> <small>' + data['domain'] + '</small></h4>';
                html += '<p>' + data['explain'] + '</p>';
                if (data['matched_rule']) html += '<p class="text-muted">matched: <code>' + data['matched_rule'] + '</code> (' + data['matched_file'] + ')</p>';
                if (data['sync_pf']) html += '<p class="text-muted">will sync to pf table</p>';
                $("#testResult").html(html);
            });
        });
        $("#testDomain").keypress(function(e) {
            if (e.which == 13) { $("#testDomainAct").click(); return false; }
        });
    });
</script>

<div class="content-box">
    <p class="text-muted">{{ lang._('Simulate the routing decision for a domain by rule analysis (no real DNS queries).') }}</p>
    <div class="form-inline">
        <input type="text" id="testDomain" class="form-control" placeholder="example.com" style="min-width:300px;"/>
        <button class="btn btn-primary btn-sm" id="testDomainAct" type="button">{{ lang._('Test') }}</button>
    </div>
    <div id="testResult" style="margin-top:15px;"></div>
</div>
