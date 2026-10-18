<?php

/* Copyright (C) 2026 nxovaeng
 * All rights reserved.
 */

namespace OPNsense\Mosdns\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;
use OPNsense\Core\Backend;

class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '\OPNsense\Mosdns\Mosdns';
    protected static $internalServiceName = 'mosdns';
    protected static $internalServiceTemplate = 'OPNsense/Mosdns';
    protected static $internalServiceEnabled = 'general.enabled';

    /**
     * Reconfigure mosdns (base behavior) and bounce the companion
     * pf-aliasd daemon so its rc.conf.d settings also apply.
     * A disabled service is stopped, not started (rc.conf.d says NO).
     */
    public function reconfigureAction()
    {
        $ret = parent::reconfigureAction();
        if (isset($ret['status']) && $ret['status'] == 'ok') {
            (new Backend())->configdRun('mosdns pfaliasd.restart');
        }
        return $ret;
    }
}
