<?php

/* Copyright (C) 2026 nxovaeng
 * All rights reserved.
 */

namespace OPNsense\Tun2socks\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;
use OPNsense\Core\Backend;

class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '\OPNsense\Tun2socks\Tun2socks';
    protected static $internalServiceName = 'tun2socks';
    protected static $internalServiceTemplate = 'OPNsense/Tun2socks';
    protected static $internalServiceEnabled = 'tunnel.enabled';

    /**
     * Tail the hev-socks5-tunnel log (last 100 lines).
     */
    public function logAction()
    {
        $response = '';
        if ($this->request->isPost()) {
            $response = (new Backend())->configdRun('tun2socks log');
        }
        return ['response' => $response];
    }
}
