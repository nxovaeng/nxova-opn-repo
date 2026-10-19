{#
 # Copyright (C) 2026 nxovaeng
 # All rights reserved.
 #}

<script>
    $(document).ready(function() {
        function refreshLog() {
            $("#refreshLogAct_progress").addClass("fa fa-spinner fa-pulse");
            ajaxCall(url="/api/tun2socks/service/log", sendData={}, callback=function(data, status) {
                $("#refreshLogAct_progress").removeClass("fa fa-spinner fa-pulse");
                $("#serviceLog").text(data['response'] || status);
            });
        }
        $("#refreshLogAct").click(function() { refreshLog(); });
        refreshLog();
    });
</script>

<div class="content-box">
    <div class="col-md-12">
        <button class="btn btn-default btn-sm" id="refreshLogAct" type="button">
            {{ lang._('刷新') }} <i id="refreshLogAct_progress"></i>
        </button>
        <span class="text-muted" style="margin-left:10px;">{{ lang._('守护进程日志最后 100 行') }}</span>
    </div>
    <div class="col-md-12" style="margin-top: 10px;">
        <pre id="serviceLog" style="max-height: 500px; overflow-y: auto; background:#000; color:#0f0;"></pre>
    </div>
</div>
