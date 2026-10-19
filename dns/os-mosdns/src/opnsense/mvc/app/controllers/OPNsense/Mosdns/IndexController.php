<?php

/* Copyright (C) 2026 nxovaeng
 * All rights reserved.
 */

namespace OPNsense\Mosdns;

use OPNsense\Base\IndexController as BaseIndexController;

class IndexController extends BaseIndexController
{
    public function indexAction()
    {
        $this->view->generalForm = $this->getForm('general');
        $this->view->forwardForm = $this->getForm('forward');
        $this->view->pfaliasForm = $this->getForm('pfalias');
        $this->view->pick('OPNsense/Mosdns/index');
    }

    public function pfaliasdAction()
    {
        $this->view->pfaliasdForm = $this->getForm('pfaliasd');
        $this->view->pick('OPNsense/Mosdns/pfaliasd');
    }

    public function rulesAction()
    {
        $this->view->pick('OPNsense/Mosdns/rules');
    }

    public function testAction()
    {
        $this->view->pick('OPNsense/Mosdns/test');
    }

    public function logsAction()
    {
        $this->view->pick('OPNsense/Mosdns/logs');
    }
}
