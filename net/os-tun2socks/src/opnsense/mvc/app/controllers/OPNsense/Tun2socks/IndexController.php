<?php

/* Copyright (C) 2026 nxovaeng
 * All rights reserved.
 */

namespace OPNsense\Tun2socks;

use OPNsense\Base\IndexController as BaseIndexController;

class IndexController extends BaseIndexController
{
    public function indexAction()
    {
        $this->view->tunnelForm = $this->getForm('tunnel');
        $this->view->socks5Form = $this->getForm('socks5');
        $this->view->miscForm = $this->getForm('misc');
        $this->view->pick('OPNsense/Tun2socks/index');
    }

    public function logsAction()
    {
        $this->view->pick('OPNsense/Tun2socks/logs');
    }
}
