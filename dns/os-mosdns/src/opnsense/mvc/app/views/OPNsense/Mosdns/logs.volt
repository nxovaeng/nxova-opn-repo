{#
 # Copyright (C) 2026 nxovaeng
 # All rights reserved.
 #}

<script>
    $(document).ready(function() {
        var currentTarget = 'mosdns';
        function clearLabel() {
            return currentTarget === 'aliasd' ? '清空 pf-aliasd 日志' : '清空 mosdns 日志';
        }
        function refreshLog(target) {
            currentTarget = target;
            $("#clearLogAct").text(clearLabel());
            ajaxCall(url="/api/mosdns/service/log/" + target, sendData={lines: 200}, callback=function(data, status) {
                $("#mosdnsLog").text(data['log'] || '');
            });
        }
        $("#refreshMosdnsLog").click(function() { refreshLog('mosdns'); });
        $("#refreshAliasdLog").click(function() { refreshLog('aliasd'); });
        $("#clearLogAct").click(function() {
            ajaxCall(url="/api/mosdns/service/clearLog/" + currentTarget, sendData={}, callback=function(data, status) {
                refreshLog(currentTarget);
            });
        });
        refreshLog('mosdns');
    });
</script>

<div class="content-box">
    <p>
        <button class="btn btn-default btn-sm" id="refreshMosdnsLog" type="button">mosdns {{ lang._('Refresh') }}</button>
        <button class="btn btn-default btn-sm" id="refreshAliasdLog" type="button">pf-aliasd {{ lang._('Refresh') }}</button>
        <button class="btn btn-default btn-sm" id="clearLogAct" type="button">清空 mosdns 日志</button>
    </p>
    <pre id="mosdnsLog" style="max-height:500px; overflow:auto; background:#000; color:#0f0;"></pre>
</div>
