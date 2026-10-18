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
        $this->view->pfaliasdForm = $this->getForm('pfaliasd');
        $this->view->pick('OPNsense/Mosdns/index');
    }
}
