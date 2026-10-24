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
        // No merge exists: the generated config lists each enabled rule
        // group's file directly. Applying only has to make sure those
        // files exist (prepare) and refresh the shared groups.json.
        $prep = $this->runPrepare();
        $ret = parent::reconfigureAction();
        if (isset($ret['status']) && $ret['status'] == 'ok') {
            $created = $this->ensureAliasTable();
            if ($created) {
                $ret['status_msg'] = trim(($ret['status_msg'] ?? '') .
                    ' 已自动创建别名 ' . $created . '（外部/高级），pf 表已生成。');
            } elseif ($created === false) {
                $ret['status_msg'] = trim(($ret['status_msg'] ?? '') .
                    ' 警告：自动创建别名失败，请到防火墙 → 别名手动新建同名“外部（高级）”别名。');
            }
            // pf-aliasd is NOT restarted here on purpose: the two services
            // are independent (only the menu groups them). The daemon has
            // its own Apply (reconfigurePfaliasdAction below); a mosdns
            // config change does not need a daemon restart.
            if (!empty($prep['warnings'])) {
                $ret['status_msg'] = trim(($ret['status_msg'] ?? '') .
                    ' 规则警告：' . implode('；', $prep['warnings']));
            }
        }
        return $ret;
    }

    /**
     * Apply for the pf-aliasd daemon ONLY: regenerate templates (its
     * rc.conf.d toggle lives in the shared OPNsense/Mosdns template dir),
     * make sure the sync target alias exists, restart the daemon. mosdns
     * itself is never stopped or restarted here -- the services are
     * separate; only the menu groups them under MosDNS.
     */
    public function reconfigurePfaliasdAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed'];
        }
        $backend = new Backend();
        $tpl = trim($backend->configdpRun('template reload', ['OPNsense/Mosdns']));
        if ($tpl !== 'OK') {
            return ['status' => 'failed', 'status_msg' => '模板生成失败：' . $tpl];
        }
        $ret = ['status' => 'ok'];
        $created = $this->ensureAliasTable();
        if ($created) {
            $ret['status_msg'] = '已自动创建别名 ' . $created . '（外部/高级），pf 表已生成。';
        } elseif ($created === false) {
            $ret['status_msg'] = '警告：自动创建别名失败，请到防火墙 → 别名手动新建同名“外部（高级）”别名。';
        }
        $backend->configdRun('mosdns pfaliasd restart');
        return $ret;
    }

    /**
     * Make sure an "External (advanced)" firewall alias exists for the pf
     * sync target table. A pf table only exists once the ruleset defines
     * it, and an External alias is exactly that definition (core never
     * manages its content -- pf-aliasd does). A missing table used to mean
     * silent sync failure unless the user created the alias by hand, so
     * Apply creates it when missing. An existing alias is never touched.
     *
     * Returns the created table name, null when nothing was needed, or
     * false on failure.
     */
    private function ensureAliasTable()
    {
        $mdl = $this->getModel();
        if ($mdl === null || (string)$mdl->pfalias->enabled !== '1') {
            return null;
        }
        $table = trim((string)$mdl->pfalias->table);
        if ($table === '') {
            return null;
        }
        try {
            $aliasMdl = new \OPNsense\Firewall\Alias();
            foreach ($aliasMdl->aliases->alias->iterateItems() as $item) {
                if ((string)$item->name === $table) {
                    return null;
                }
            }
            $node = $aliasMdl->aliases->alias->Add();
            $node->enabled = '1';
            $node->name = $table;
            $node->type = 'external';
            $node->description = 'os-mosdns pf-aliasd sync target (auto-created on Apply)';
            $aliasMdl->serializeToConfig();
            // serializeToConfig only stages into the in-memory config;
            // without an explicit save the alias vanishes with the request.
            \OPNsense\Core\Config::getInstance()->save();
            (new Backend())->configdRun('filter reload');
            return $table;
        } catch (\Throwable $e) {
            return false;
        }
    }

    /* ------------------------------------------------------------------ */
    /* Rule groups: canonical plain-txt lists. The generated mosdns      */
    /* config lists each enabled group's file in its domain_set (mosdns  */
    /* unions them itself -- no merge step); other tools read            */
    /* groups.json.                                                      */
    /* ------------------------------------------------------------------ */

    private function findGroup($uuid)
    {
        $mdl = $this->getModel();
        if ($mdl === null) {
            return null;
        }
        foreach ($mdl->rulegroups->group->iterateItems() as $key => $group) {
            if ((string)$key === (string)$uuid) {
                return $group;
            }
            $ref = (string)$group->__reference;
            if ($ref !== '' && substr($ref, -strlen((string)$uuid)) === (string)$uuid) {
                return $group;
            }
        }
        return null;
    }

    private function groupsManifest()
    {
        $list = [];
        $mdl = $this->getModel();
        if ($mdl !== null) {
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

    private function runPrepare()
    {
        $tmp = tempnam('/tmp', 'mosdns-groups-');
        file_put_contents($tmp, json_encode($this->groupsManifest()));
        $raw = trim((new Backend())->configdpRun('mosdns rules prepare', [$tmp]));
        @unlink($tmp);
        $data = json_decode($raw, true);
        return is_array($data) ? $data : ['result' => 'failed', 'output' => $raw];
    }

    /**
     * Apply the rule groups: ensure their files exist, regenerate the
     * mosdns config (its domain_set file lists come from the model), and
     * restart mosdns. No merging -- mosdns unions the group files itself.
     */
    public function applyRulesAction()
    {
        if (!$this->request->isPost()) {
            return ['result' => 'failed'];
        }
        $prep = $this->runPrepare();
        if (($prep['result'] ?? '') !== 'ok') {
            return $prep;
        }
        $backend = new Backend();
        $tpl = trim($backend->configdpRun('template reload', ['OPNsense/Mosdns']));
        if ($tpl !== 'OK') {
            return ['result' => 'failed', 'error' => '模板生成失败：' . $tpl];
        }
        $backend->configdRun('mosdns restart');
        return $prep;
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
        $raw = trim((new Backend())->configdpRun('mosdns rules get_group',
            [$uuid, (string)$group->source]));
        $data = json_decode($raw, true);
        return is_array($data) ? $data : ['result' => 'failed', 'error' => $raw];
    }

    /**
     * Save a local group's content (validated by rule_tool). Body:
     * {content: "..."}. Writing only touches the group's file; the
     * change goes live at the next Apply (applyRulesAction).
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
        $result = trim((new Backend())->configdpRun('mosdns rules install_group', [$uuid, $tmp]));
        @unlink($tmp);
        if ($result !== 'OK') {
            $data = json_decode($result, true);
            if (is_array($data) && !empty($data['errors'])) {
                return ['result' => 'failed', 'errors' => $data['errors']];
            }
            return ['result' => 'failed', 'output' => $result];
        }
        // Deliberately no restart here: editing only writes the group's
        // file. It goes live once, when the user clicks Apply
        // (applyRulesAction: template reload + mosdns restart).
        return ['result' => 'saved'];
    }

    /**
     * Fetch a remote group's URL into its cache (sanitized; a failed fetch
     * keeps the old cache). Like editing, this only updates the file --
     * it goes live at the next Apply (applyRulesAction).
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
        $raw = trim((new Backend())->configdpRun('mosdns rules fetch_group', [$uuid, $url]));
        $data = json_decode($raw, true);
        if (!is_array($data) || ($data['result'] ?? '') !== 'ok') {
            return is_array($data) ? $data : ['result' => 'failed', 'error' => $raw];
        }
        return ['result' => 'ok', 'count' => $data['count'] ?? 0,
            'dropped' => $data['dropped'] ?? 0, 'converted' => $data['converted'] ?? 0];
    }

    /**
     * Test a domain against the current rule groups/mode (the simulator
     * reads the same group files the generated config lists). Returns
     * the routing decision.
     */
    public function testDomainAction()
    {
        $domain = $this->request->get('domain', 'string', '');
        if ($domain === '') {
            return ['result' => 'failed', 'error' => 'empty domain'];
        }
        $tmp = tempnam('/tmp', 'mosdns-groups-');
        file_put_contents($tmp, json_encode($this->groupsManifest()));
        $raw = trim((new Backend())->configdpRun('mosdns rules test', [$domain, $tmp]));
        @unlink($tmp);
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
        $raw = $backend->configdpRun($action, [(string)$lines]);
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

    /**
     * Flush the managed alias tables right now: the daemon drops its TTL
     * records and the tracked pf entries, and a pfctl sweep clears any
     * untracked leftovers. New resolutions refill the tables.
     */
    public function pfaliasdFlushAction()
    {
        if (!$this->request->isPost()) {
            return ['result' => 'failed'];
        }
        $mdl = $this->getModel();
        $socket = trim((string)$mdl->pfaliasd->socket_path);
        if ($socket === '') {
            $socket = '/var/run/pf-aliasd.sock';
        }
        $tables = [];
        $target = trim((string)$mdl->pfalias->table);
        if ($target !== '') {
            $tables[] = $target;
        }
        foreach (explode(',', (string)$mdl->pfaliasd->flush_tables) as $extra) {
            $extra = trim($extra);
            if ($extra !== '' && !in_array($extra, $tables, true)) {
                $tables[] = $extra;
            }
        }
        if (empty($tables)) {
            return ['result' => 'failed', 'error' => 'no alias tables configured'];
        }
        $raw = trim((new Backend())->configdpRun('mosdns pfaliasd flush', [$socket, implode(',', $tables)]));
        $data = json_decode($raw, true);
        return is_array($data) ? $data : ['result' => 'failed', 'output' => $raw];
    }
}
