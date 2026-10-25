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
     *
     * Order matters: template reload FIRST, then generate. The generator
     * reads model.json, which is dumped by the template; generating
     * before the reload (the old order) built the config from the
     * PREVIOUS model.json, so the first Apply after any model change
     * started stale config and only the second Apply picked it up.
     */
    public function reconfigureAction()
    {
        $ret = ['status' => 'failed'];
        if ($this->request->isPost()) {
            $backend = new Backend();
            $backend->configdpRun('template reload', ['OPNsense/Xray']);
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
     * Probe the live default outbound path (see test_outbound.py).
     * The script always exits 0 with one JSON object; pass it through.
     */
    public function testOutboundAction()
    {
        if (!$this->request->isPost()) {
            return ['ok' => false, 'http_code' => 0, 'ms' => 0, 'error' => '需要 POST'];
        }
        $backend = new Backend();
        $raw = trim($backend->configdRun('xray test_outbound'));
        $data = json_decode($raw, true);
        if (is_array($data)) {
            return $data;
        }
        return ['ok' => false, 'http_code' => 0, 'ms' => 0,
                'error' => $raw !== '' ? $raw : '探针无输出'];
    }

    /**
     * Last config generation / validation error, if any (P0-2).
     * Written by generate_config.py on failure, cleared on success.
     */
    public function getValidationErrorAction()
    {
        $backend = new Backend();
        $raw = trim($backend->configdRun('xray show_validation_error'));
        return ['result' => 'ok', 'error' => $raw];
    }

    /**
     * Tail the xray log.
     */
    public function logAction()
    {
        $lines = (int)$this->request->get('lines', 'int', 100);
        $lines = max(1, min(500, $lines));
        $backend = new Backend();
        $raw = $backend->configdpRun('xray show_log', [(string)$lines]);
        return ['result' => 'ok', 'log' => $raw];
    }

    /**
     * Truncate the xray log (manual clear; the file grows fast at
     * debug level and there is no rotation daemon wired up).
     */
    public function clearLogAction()
    {
        $backend = new Backend();
        $raw = trim($backend->configdRun('xray clear_log'));
        return ['result' => 'ok', 'output' => $raw];
    }
}
