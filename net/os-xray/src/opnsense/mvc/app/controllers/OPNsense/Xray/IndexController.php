<?php

/* Copyright (C) 2026 nxovaeng
 * All rights reserved.
 */

namespace OPNsense\Xray;

use OPNsense\Base\IndexController as BaseIndexController;

class IndexController extends BaseIndexController
{
    public function indexAction()
    {
        $this->view->generalForm = $this->getForm('general');
        $this->view->nodeForm = $this->getForm('node');
        $this->view->inboundForm = $this->getForm('inbound');
        $this->view->ruleForm = $this->getForm('rule');
        $this->view->subscriptionForm = $this->getForm('subscription');
        $this->view->pick('OPNsense/Xray/index');
    }
}
