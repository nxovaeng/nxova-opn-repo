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
     * Log file the daemon writes to (rc.d daemon -o follows the same
     * setting). Both tail and clear take it from the model so they can
     * never disagree with each other or with the daemon.
     */
    private function logFile()
    {
        $path = trim((string)$this->getModel()->misc->log_file);
        return $path !== '' ? $path : '/var/log/tun2socks.log';
    }

    /**
     * Tail the tun2socks log (last 100 lines).
     */
    public function logAction()
    {
        $response = '';
        if ($this->request->isPost()) {
            $response = (new Backend())->configdpRun('tun2socks log', [$this->logFile()]);
        }
        return ['response' => $response];
    }

    public function clearLogAction()
    {
        $response = '';
        if ($this->request->isPost()) {
            $response = trim((new Backend())->configdpRun('tun2socks clear_log', [$this->logFile()]));
        }
        return ['response' => $response];
    }
}
