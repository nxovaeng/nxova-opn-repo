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
            (new Backend())->configdRun('mosdns pfaliasd restart');
        }
        return $ret;
    }

    /**
     * List rule files with stats.
     */
    public function listRulesAction()
    {
        $raw = trim((new Backend())->configdRun('mosdns rules.list'));
        $data = json_decode($raw, true);
        return ['result' => 'ok', 'files' => is_array($data) ? $data : []];
    }

    /**
     * Get a rule file's content.
     */
    public function getRuleAction($name)
    {
        $name = basename($name);
        $raw = (new Backend())->configdRun('mosdns rules.get', [$name]);
        return ['result' => 'ok', 'name' => $name, 'content' => $raw];
    }

    /**
     * Save a rule file (custom-*.txt only). Body: {content: "..."}.
     */
    public function setRuleAction($name)
    {
        if (!$this->request->isPost()) {
            return ['result' => 'failed'];
        }
        $name = basename($name);
        $content = $this->request->getPost('content', 'string', '');
        $tmp = tempnam('/tmp', 'mosdns-rule-');
        file_put_contents($tmp, $content);
        $result = trim((new Backend())->configdRun('mosdns rules.install', [$name, $tmp]));
        @unlink($tmp);
        return ['result' => $result === 'OK' ? 'saved' : 'failed', 'output' => $result];
    }

    /**
     * Test a domain against the current rules/mode. Returns the routing decision.
     */
    public function testDomainAction()
    {
        $domain = $this->request->get('domain', 'string', '');
        if ($domain === '') {
            return ['result' => 'failed', 'error' => 'empty domain'];
        }
        $raw = trim((new Backend())->configdRun('mosdns rules.test', [$domain]));
        $data = json_decode($raw, true);
        if (!is_array($data)) {
            return ['result' => 'failed', 'error' => $raw];
        }
        return array_merge(['result' => 'ok'], $data);
    }

    /**
     * Tail logs.
     */
    public function logAction($target = 'mosdns')
    {
        $lines = (int)$this->request->get('lines', 100);
        $lines = max(1, min(500, $lines));
        $backend = new Backend();
        $action = $target === 'aliasd' ? 'mosdns show_aliasd_log' : 'mosdns show_log';
        $raw = $backend->configdRun($action, [(string)$lines]);
        return ['result' => 'ok', 'log' => $raw];
    }
}
