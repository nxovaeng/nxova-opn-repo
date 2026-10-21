<?php

/* Copyright (C) 2026 nxovaeng
 * All rights reserved.
 */

namespace OPNsense\Xray\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;
use OPNsense\Core\Backend;

class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '\OPNsense\Xray\Xray';
    protected static $internalServiceName = 'xray';
    protected static $internalServiceTemplate = 'OPNsense/Xray';
    protected static $internalServiceEnabled = 'general.enabled';

    /**
     * Regenerate xray config from the model (Python generator, runs
     * `xray -test` for validation), then start/restart the service.
     */
    public function reconfigureAction()
    {
        $ret = ['status' => 'failed'];
        if ($this->request->isPost()) {
            $backend = new Backend();
            $gen = trim($backend->configdRun('xray generate_config'));
            if ($gen !== 'OK') {
                $ret['status_msg'] = $gen !== '' ? $gen : 'config generation failed';
                return $ret;
            }
            // hand over to the base implementation (template reload + start)
            $ret = parent::reconfigureAction();
        }
        return $ret;
    }

    /**
     * Preview the generated xray config without applying.
     */
    public function previewAction()
    {
        if (!$this->request->isPost()) {
            return ['result' => 'failed'];
        }
        $backend = new Backend();
        $raw = trim($backend->configdRun('xray preview_config'));
        $data = json_decode($raw, true);
        if (!is_array($data)) {
            return ['result' => 'failed', 'error' => $raw];
        }
        return ['result' => 'ok', 'config' => $data];
    }

    /**
     * Validate current config with `xray -test`.
     */
    public function testConfigAction()
    {
        if (!$this->request->isPost()) {
            return ['result' => 'failed'];
        }
        $backend = new Backend();
        $raw = trim($backend->configdRun('xray test_config'));
        return ['result' => $raw === 'OK' ? 'ok' : 'failed', 'output' => $raw];
    }

    /**
     * Tail the xray log.
     */
    public function logAction()
    {
        $lines = (int)$this->request->get('lines', 'int', 100);
        $lines = max(1, min(500, $lines));
        $backend = new Backend();
        $raw = $backend->configdRun('xray show_log', [(string)$lines]);
        return ['result' => 'ok', 'log' => $raw];
    }
}
