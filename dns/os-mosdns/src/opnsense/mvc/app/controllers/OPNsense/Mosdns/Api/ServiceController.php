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
        // saving/applying settings also re-merges the rule groups into the
        // built-in custom-*.txt files and refreshes the shared groups.json
        $merge = $this->runMerge();
        $ret = parent::reconfigureAction();
        if (isset($ret['status']) && $ret['status'] == 'ok') {
            (new Backend())->configdRun('mosdns pfaliasd restart');
            if (!empty($merge['warnings'])) {
                $ret['status_msg'] = trim(($ret['status_msg'] ?? '') .
                    ' 规则合并警告：' . implode('；', $merge['warnings']));
            }
        }
        return $ret;
    }

    /* ------------------------------------------------------------------ */
    /* Rule groups: canonical plain-txt lists. mosdns merges the enabled  */
    /* groups into custom-*.txt; other tools (xray) read groups.json.     */
    /* ------------------------------------------------------------------ */

    private function findGroup($uuid)
    {
        $mdl = $this->getModel();
        if ($mdl === null || !isset($mdl->rulegroups)) {
            return null;
        }
        return $mdl->rulegroups->group->getNodeByReference('uuid.' . $uuid);
    }

    private function groupsManifest()
    {
        $list = [];
        $mdl = $this->getModel();
        if ($mdl !== null && isset($mdl->rulegroups)) {
            foreach ($mdl->rulegroups->group->iterateItems() as $uuid => $g) {
                $list[] = [
                    'uuid' => $uuid,
                    'name' => (string)$g->name,
                    'type' => (string)$g->type,
                    'tags' => (string)$g->tags,
                    'source' => (string)$g->source,
                    'url' => (string)$g->url,
                    'enabled' => (string)$g->enabled,
                ];
            }
        }
        return $list;
    }

    private function runMerge()
    {
        $tmp = tempnam('/tmp', 'mosdns-groups-');
        file_put_contents($tmp, json_encode($this->groupsManifest()));
        $raw = trim((new Backend())->configdRun('mosdns rules merge', [$tmp]));
        @unlink($tmp);
        $data = json_decode($raw, true);
        return is_array($data) ? $data : ['result' => 'failed', 'output' => $raw];
    }

    /**
     * Merge enabled groups into custom-*.txt (+ export groups.json), then
     * restart mosdns so the merged lists take effect.
     */
    public function mergeRulesAction()
    {
        if (!$this->request->isPost()) {
            return ['result' => 'failed'];
        }
        $merge = $this->runMerge();
        if (($merge['result'] ?? '') === 'ok') {
            (new Backend())->configdRun('mosdns restart');
        }
        return $merge;
    }

    /**
     * Read a group's content (local file, or the remote group's cache).
     */
    public function getGroupContentAction($uuid)
    {
        $group = $this->findGroup($uuid);
        if ($group === null) {
            return ['result' => 'failed', 'error' => 'group not found'];
        }
        $raw = trim((new Backend())->configdRun('mosdns rules get_group',
            [$uuid, (string)$group->source]));
        $data = json_decode($raw, true);
        return is_array($data) ? $data : ['result' => 'failed', 'error' => $raw];
    }

    /**
     * Save a local group's content (validated by rule_tool), then merge
     * and restart so the change is live immediately.
     * Body: {content: "..."}.
     */
    public function setGroupContentAction($uuid)
    {
        if (!$this->request->isPost()) {
            return ['result' => 'failed'];
        }
        $group = $this->findGroup($uuid);
        if ($group === null) {
            return ['result' => 'failed', 'error' => 'group not found'];
        }
        if ((string)$group->source !== 'local') {
            return ['result' => 'failed', 'error' => 'remote group content comes from its URL'];
        }
        $content = $this->request->getPost('content', 'string', '');
        $tmp = tempnam('/tmp', 'mosdns-group-');
        file_put_contents($tmp, $content);
        $result = trim((new Backend())->configdRun('mosdns rules install_group', [$uuid, $tmp]));
        @unlink($tmp);
        if ($result !== 'OK') {
            $data = json_decode($result, true);
            if (is_array($data) && !empty($data['errors'])) {
                return ['result' => 'failed', 'errors' => $data['errors']];
            }
            return ['result' => 'failed', 'output' => $result];
        }
        $merge = $this->runMerge();
        if (($merge['result'] ?? '') === 'ok') {
            (new Backend())->configdRun('mosdns restart');
        }
        return ['result' => 'saved', 'merge' => $merge];
    }

    /**
     * Fetch a remote group's URL into its cache (validated; a failed fetch
     * keeps the old cache), then merge and restart.
     */
    public function fetchGroupAction($uuid)
    {
        if (!$this->request->isPost()) {
            return ['result' => 'failed'];
        }
        $group = $this->findGroup($uuid);
        if ($group === null) {
            return ['result' => 'failed', 'error' => 'group not found'];
        }
        $url = trim((string)$group->url);
        if ($url === '' || !filter_var($url, FILTER_VALIDATE_URL)) {
            return ['result' => 'failed', 'error' => 'invalid url'];
        }
        $raw = trim((new Backend())->configdRun('mosdns rules fetch_group', [$uuid, $url]));
        $data = json_decode($raw, true);
        if (!is_array($data) || ($data['result'] ?? '') !== 'ok') {
            return is_array($data) ? $data : ['result' => 'failed', 'error' => $raw];
        }
        $merge = $this->runMerge();
        if (($merge['result'] ?? '') === 'ok') {
            (new Backend())->configdRun('mosdns restart');
        }
        return ['result' => 'ok', 'count' => $data['count'] ?? 0, 'merge' => $merge];
    }

    /**
     * List rule files with stats.
     */
    public function listRulesAction()
    {
        $raw = trim((new Backend())->configdRun('mosdns rules list'));
        $data = json_decode($raw, true);
        return ['result' => 'ok', 'files' => is_array($data) ? $data : []];
    }

    /**
     * Get a rule file's content.
     */
    public function getRuleAction($name)
    {
        $name = basename($name);
        $raw = (new Backend())->configdRun('mosdns rules get', [$name]);
        return ['result' => 'ok', 'name' => $name, 'content' => $raw];
    }

    /**
     * Save a rule file (custom-*.txt only). Body: {content: "..."}.
     * Content is validated by rule_tool.py before install; on validation
     * failure the live file is untouched and errors are returned.
     * mosdns loads rule files at startup, so restart it to apply.
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
        $result = trim((new Backend())->configdRun('mosdns rules install', [$name, $tmp]));
        @unlink($tmp);
        if ($result === 'OK') {
            // rule files are read at mosdns startup; restart to reload them
            (new Backend())->configdRun('mosdns restart');
            return ['result' => 'saved'];
        }
        $data = json_decode($result, true);
        if (is_array($data) && !empty($data['errors'])) {
            return ['result' => 'failed', 'errors' => $data['errors']];
        }
        return ['result' => 'failed', 'output' => $result];
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
        $raw = trim((new Backend())->configdRun('mosdns rules test', [$domain]));
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
        $lines = (int)$this->request->get('lines', 'int', 100);
        $lines = max(1, min(500, $lines));
        $backend = new Backend();
        $action = $target === 'aliasd' ? 'mosdns show_aliasd_log' : 'mosdns show_log';
        $raw = $backend->configdRun($action, [(string)$lines]);
        return ['result' => 'ok', 'log' => $raw];
    }

    /**
     * pf-aliasd companion daemon controls. configd action names are nested
     * (mosdns -> pfaliasd -> ...), so space-separated invocation is required.
     */
    public function pfaliasdStatusAction()
    {
        $raw = trim((new Backend())->configdRun('mosdns pfaliasd status'));
        $running = stripos($raw, 'is running') !== false;
        return ['status' => $running ? 'running' : 'stopped', 'output' => $raw];
    }

    public function pfaliasdStartAction()
    {
        $raw = trim((new Backend())->configdRun('mosdns pfaliasd start'));
        return ['status' => 'ok', 'output' => $raw];
    }

    public function pfaliasdStopAction()
    {
        $raw = trim((new Backend())->configdRun('mosdns pfaliasd stop'));
        return ['status' => 'ok', 'output' => $raw];
    }

    public function pfaliasdRestartAction()
    {
        $raw = trim((new Backend())->configdRun('mosdns pfaliasd restart'));
        return ['status' => 'ok', 'output' => $raw];
    }
}
