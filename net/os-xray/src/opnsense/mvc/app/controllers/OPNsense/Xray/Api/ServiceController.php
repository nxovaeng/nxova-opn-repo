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
     * Probe one site through the live default outbound path
     * (see test_outbound.py). Site is an allowlisted key, never a
     * raw URL from the client. The script always exits 0 with one
     * JSON object; pass it through.
     *
     * POST `inbound` (optional) selects the socks entry: a model
     * inbound uuid, or 'builtin-tun2socks-in'. Absent/empty means
     * tun2socks-in (127.0.0.1:10808), the historical default, so the
     * nodes-page button (which sends no inbound) is unchanged.
     * Only enabled, no-auth socks inbounds resolve; anything else
     * (unknown uuid, disabled, non-socks, auth) is an explicit
     * error, never a silent fallback to 10808: falling back would
     * report the wrong entry's result as the selected entry's.
     * A 0.0.0.0 listen address maps to 127.0.0.1 for curl.
     */
    public function testOutboundAction()
    {
        if (!$this->request->isPost()) {
            return ['ok' => false, 'http_code' => 0, 'ms' => 0, 'error' => '需要 POST'];
        }
        $site = $this->request->getPost('site');
        if (!in_array($site, ['google', 'github', 'youtube', 'aliyun', 'qq', 'youku'], true)) {
            $site = 'google';
        }
        $proxy = '127.0.0.1:10808';
        $inbound = trim((string)$this->request->getPost('inbound', 'string', ''));
        if ($inbound !== '' && $inbound !== 'builtin-tun2socks-in') {
            $found = null;
            $mdl = new \OPNsense\Xray\Xray();
            foreach ($mdl->inbounds->inbound->iterateItems() as $uuid => $ib) {
                if ($uuid === $inbound) {
                    $found = $ib;
                    break;
                }
            }
            if ($found === null) {
                return ['ok' => false, 'http_code' => 0, 'ms' => 0, 'error' => 'socks 入站不存在'];
            }
            if ((string)$found->enabled !== '1') {
                return ['ok' => false, 'http_code' => 0, 'ms' => 0, 'error' => 'socks 入站未启用'];
            }
            if ((string)$found->protocol !== 'socks') {
                return ['ok' => false, 'http_code' => 0, 'ms' => 0, 'error' => '该入站不是 socks 协议'];
            }
            if (trim((string)$found->username) !== '') {
                return ['ok' => false, 'http_code' => 0, 'ms' => 0, 'error' => '该 socks 入站需认证，暂不支持探针'];
            }
            $listen = trim((string)$found->listen);
            if ($listen === '' || $listen === '0.0.0.0') {
                $listen = '127.0.0.1';
            }
            $port = (int)(string)$found->port;
            if ($port < 1 || $port > 65535) {
                return ['ok' => false, 'http_code' => 0, 'ms' => 0, 'error' => 'socks 入站端口无效'];
            }
            $proxy = $listen . ':' . $port;
        }
        $backend = new Backend();
        $raw = trim($backend->configdpRun('xray test_outbound', [$site, $proxy]));
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
