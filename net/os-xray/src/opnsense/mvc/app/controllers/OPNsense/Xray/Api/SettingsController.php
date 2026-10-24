<?php

/* Copyright (C) 2026 nxovaeng
 * All rights reserved.
 */

namespace OPNsense\Xray\Api;

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Backend;

class SettingsController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'xray';
    protected static $internalModelClass = '\OPNsense\Xray\Xray';

    /**
     * Find an ArrayField item by its container uuid (iterateItems keys).
     */
    private function findByUuid($collection, $uuid)
    {
        foreach ($collection->iterateItems() as $key => $item) {
            if ($key === $uuid) {
                return $item;
            }
        }
        return null;
    }

    /**
     * Search nodes/inbounds/rules/subscriptions (bootgrid).
     * GET /api/xray/settings/searchNodes etc. are auto-provided by
     * ApiMutableModelControllerBase via getModel()->nodes->... ?
     * We expose explicit search wrappers for the grids.
     */
    public function searchNodesAction()
    {
        return $this->searchBase('nodes.node');
    }

    public function searchInboundsAction()
    {
        return $this->searchBase('inbounds.inbound');
    }

    public function searchRulesAction()
    {
        return $this->searchBase('rules.rule');
    }

    public function searchSubscriptionsAction()
    {
        return $this->searchBase('subscriptions.subscription');
    }

    public function getNodeAction($uuid = null)
    {
        return $this->getBase('node', 'nodes.node', $uuid);
    }

    public function addNodeAction()
    {
        return $this->addBase('node', 'nodes.node');
    }

    public function setNodeAction($uuid)
    {
        return $this->setBase('node', 'nodes.node', $uuid);
    }

    public function delNodeAction($uuid)
    {
        return $this->delBase('nodes.node', $uuid);
    }

    public function toggleNodeAction($uuid, $enabled = null)
    {
        return $this->toggleBase('nodes.node', $uuid, $enabled);
    }

    public function getInboundAction($uuid = null)
    {
        return $this->getBase('inbound', 'inbounds.inbound', $uuid);
    }

    public function addInboundAction()
    {
        return $this->addBase('inbound', 'inbounds.inbound');
    }

    public function setInboundAction($uuid)
    {
        return $this->setBase('inbound', 'inbounds.inbound', $uuid);
    }

    public function delInboundAction($uuid)
    {
        return $this->delBase('inbounds.inbound', $uuid);
    }

    public function toggleInboundAction($uuid, $enabled = null)
    {
        return $this->toggleBase('inbounds.inbound', $uuid, $enabled);
    }

    public function getRuleAction($uuid = null)
    {
        return $this->getBase('rule', 'rules.rule', $uuid);
    }

    public function addRuleAction()
    {
        return $this->addBase('rule', 'rules.rule');
    }

    public function setRuleAction($uuid)
    {
        return $this->setBase('rule', 'rules.rule', $uuid);
    }

    public function delRuleAction($uuid)
    {
        return $this->delBase('rules.rule', $uuid);
    }

    public function toggleRuleAction($uuid, $enabled = null)
    {
        return $this->toggleBase('rules.rule', $uuid, $enabled);
    }

    public function getSubscriptionAction($uuid = null)
    {
        return $this->getBase('subscription', 'subscriptions.subscription', $uuid);
    }

    public function addSubscriptionAction()
    {
        return $this->addBase('subscription', 'subscriptions.subscription');
    }

    public function delSubscriptionAction($uuid)
    {
        // delete subscription and its nodes
        $mdl = $this->getModel();
        $sub = $this->findByUuid($mdl->subscriptions->subscription, $uuid);
        $activeUuid = (string)$mdl->general->active_node;
        $result = $this->delBase('subscriptions.subscription', $uuid);
        if ($result['result'] != 'failed' && $sub != null) {
            foreach ($mdl->nodes->node->iterateItems() as $nodeUuid => $node) {
                if ((string)$node->sub_id == $uuid) {
                    $mdl->nodes->node->del($nodeUuid);
                }
            }
            // same dangling-reference class as P0-3: if the active node
            // belonged to this subscription, clear it instead of leaving
            // a reference the generator would fail closed on
            if ($activeUuid !== '' && $this->findByUuid($mdl->nodes->node, $activeUuid) == null) {
                $mdl->general->active_node = '';
                $result['active_cleared'] = true;
            }
            $mdl->serializeToConfig();
            \OPNsense\Core\Config::getInstance()->save();
        }
        return $result;
    }

    /**
     * Set the default (active) node by uuid.
     */
    public function setActiveNodeAction($uuid)
    {
        if (!$this->request->isPost()) {
            return ['result' => 'failed'];
        }
        $mdl = $this->getModel();
        $node = $this->findByUuid($mdl->nodes->node, $uuid);
        if ($node == null) {
            return ['result' => 'failed', 'error' => 'node not found'];
        }
        $mdl->general->active_node = $uuid;
        $mdl->serializeToConfig();
        \OPNsense\Core\Config::getInstance()->save();
        return ['result' => 'saved'];
    }

    /**
     * Import nodes from pasted links (vless/vmess/trojan/ss), one per line.
     * Body: {links: "...", sub_id: "..."}.
     */
    public function importNodesAction()
    {
        if (!$this->request->isPost()) {
            return ['result' => 'failed'];
        }
        $links = $this->request->getPost('links', 'string', '');
        $subId = $this->request->getPost('sub_id', 'string', 'manual');
        $backend = new Backend();
        $raw = $backend->configdpRun('xray import_nodes', [$links, $subId]);
        $nodes = json_decode(trim($raw), true);
        if (!is_array($nodes)) {
            return ['result' => 'failed', 'error' => trim($raw)];
        }
        $mdl = $this->getModel();
        $added = 0;
        foreach ($nodes as $ndata) {
            $node = $mdl->nodes->node->add();
            foreach (['tag', 'protocol', 'address', 'port', 'network', 'security', 'sni', 'path', 'user_id', 'password', 'ss_method', 'vmess_cipher', 'flow', 'alter_id', 'host', 'fingerprint', 'allow_insecure', 'public_key', 'short_id', 'spider_x', 'params', 'sub_id'] as $f) {
                if (isset($ndata[$f])) {
                    $node->$f = $ndata[$f];
                }
            }
            $added++;
        }
        // first import sets the active node if none set
        if (empty((string)$mdl->general->active_node) && $added > 0) {
            $items = $mdl->nodes->node->iterateItems();
            $first = array_key_first($items);
            if ($first) {
                $mdl->general->active_node = $first;
            }
        }
        $mdl->serializeToConfig();
        \OPNsense\Core\Config::getInstance()->save();
        return ['result' => 'saved', 'added' => $added];
    }

    /**
     * Node identity fingerprint for subscription upsert (P0-3).
     * protocol|address|port|credential|transport|tls. SNI is deliberately
     * excluded: rotating SNI must not count as a new node (PiTun same rule).
     * NOTE: this is NOT the TLS `fingerprint` field on the node model.
     * Accepts either a parsed node array or a model item.
     */
    private function nodeFingerprint($d)
    {
        if (is_array($d)) {
            $proto = strtolower((string)($d['protocol'] ?? ''));
            $addr = (string)($d['address'] ?? '');
            $port = (string)($d['port'] ?? '');
            $cred = (string)($d['user_id'] ?? '');
            if ($cred === '') {
                $cred = (string)($d['password'] ?? '');
            }
            $net = strtolower((string)($d['network'] ?? ''));
            $sec = strtolower((string)($d['security'] ?? ''));
        } else {
            $proto = strtolower((string)$d->protocol);
            $addr = (string)$d->address;
            $port = (string)$d->port;
            $cred = (string)$d->user_id;
            if ($cred === '') {
                $cred = (string)$d->password;
            }
            $net = strtolower((string)$d->network);
            $sec = strtolower((string)$d->security);
        }
        return implode('|', [$proto, $addr, $port, $cred, $net, $sec]);
    }

    /**
     * Fetch a subscription URL, parse links, sync that subscription's nodes.
     * Body: {uuid: "..."}.
     *
     * Upsert by fingerprint (P0-3), NOT drop-all + re-add: the old code
     * deleted every node of the subscription and re-inserted them, so all
     * UUIDs changed and general.active_node pointed at a deleted UUID.
     * The generator then fell back proxy-default to freedom (direct) and
     * one refresh + one Apply silently turned ALL traffic direct.
     * Surviving nodes keep their UUIDs here, so active_node and rule
     * references stay valid across refreshes.
     */
    public function updateSubscriptionAction()
    {
        if (!$this->request->isPost()) {
            return ['result' => 'failed'];
        }
        $uuid = $this->request->getPost('uuid', 'string', '');
        $mdl = $this->getModel();
        $sub = $this->findByUuid($mdl->subscriptions->subscription, $uuid);
        if ($sub == null) {
            return ['result' => 'failed', 'error' => 'subscription not found'];
        }
        $backend = new Backend();
        $raw = $backend->configdpRun('xray fetch_subscription', [(string)$sub->url]);
        $nodes = json_decode(trim($raw), true);
        if (!is_array($nodes)) {
            return ['result' => 'failed', 'error' => trim($raw)];
        }

        $mutable = ['tag', 'protocol', 'address', 'port', 'network', 'security',
            'sni', 'path', 'user_id', 'password', 'ss_method', 'vmess_cipher',
            'flow', 'alter_id', 'host', 'fingerprint', 'allow_insecure',
            'public_key', 'short_id', 'spider_x', 'params'];
        // snapshot old rows of this subscription before touching anything
        $oldRows = [];
        foreach ($mdl->nodes->node->iterateItems() as $nodeUuid => $node) {
            if ((string)$node->sub_id != $uuid) {
                continue;
            }
            $fields = [];
            foreach ($mutable as $f) {
                $fields[$f] = (string)$node->$f;
            }
            $oldRows[$nodeUuid] = [
                'fp' => $this->nodeFingerprint($node),
                'tag' => (string)$node->tag,
                'fields' => $fields,
            ];
        }
        $activeUuid = (string)$mdl->general->active_node;
        $activeFp = isset($oldRows[$activeUuid]) ? $oldRows[$activeUuid]['fp'] : null;

        // config-referenced tags: enabled rules pointing at a node tag
        // (builtins are not node tags and never count as referenced)
        $builtins = ['', 'direct', 'block', 'dns-out', 'proxy-default'];
        $refTags = [];
        foreach ($mdl->rules->rule->iterateItems() as $rule) {
            if ((string)$rule->enabled != '1') {
                continue;
            }
            $t = (string)$rule->outbound_tag;
            if (!in_array($t, $builtins, true)) {
                $refTags[$t] = true;
            }
        }

        $byFp = [];
        foreach ($oldRows as $nodeUuid => $row) {
            if (!isset($byFp[$row['fp']])) {
                $byFp[$row['fp']] = $nodeUuid; // first row wins on duplicates
            }
        }
        $added = 0; $updated = 0; $removed = 0; $skipped = 0;
        $touched = false;
        $seenFp = [];
        foreach ($nodes as $ndata) {
            $ndata['sub_id'] = $uuid;
            $fp = $this->nodeFingerprint($ndata);
            if (isset($seenFp[$fp])) {
                $skipped++; // duplicate link inside one feed
                continue;
            }
            $seenFp[$fp] = true;
            if (isset($byFp[$fp])) {
                $nodeUuid = $byFp[$fp];
                unset($byFp[$fp]);
                $node = $this->findByUuid($mdl->nodes->node, $nodeUuid);
                $changed = false;
                foreach ($mutable as $f) {
                    if (!isset($ndata[$f])) {
                        continue;
                    }
                    if ((string)$ndata[$f] !== $oldRows[$nodeUuid]['fields'][$f]) {
                        $changed = true;
                    }
                    $node->$f = $ndata[$f];
                }
                $node->sub_id = $uuid;
                if ($changed) {
                    $updated++;
                    $newTag = isset($ndata['tag']) ? (string)$ndata['tag'] : $oldRows[$nodeUuid]['tag'];
                    if ($nodeUuid === $activeUuid
                        || isset($refTags[$oldRows[$nodeUuid]['tag']])
                        || isset($refTags[$newTag])) {
                        $touched = true;
                    }
                }
            } else {
                $node = $mdl->nodes->node->add();
                foreach ($mutable as $f) {
                    if (isset($ndata[$f])) {
                        $node->$f = $ndata[$f];
                    }
                }
                $node->sub_id = $uuid;
                $added++;
                if (isset($ndata['tag']) && isset($refTags[(string)$ndata['tag']])) {
                    $touched = true; // a rule already points at this tag
                }
            }
        }
        // rows left in $byFp disappeared from the feed
        foreach ($byFp as $nodeUuid => $fp) {
            if ($nodeUuid === $activeUuid || isset($refTags[$oldRows[$nodeUuid]['tag']])) {
                $touched = true;
            }
            $mdl->nodes->node->del($nodeUuid);
            $removed++;
        }

        // Active node remap / clear (defense: with upsert the active row
        // is only deleted when it disappeared from the feed, e.g. it was
        // the second of two duplicate-fingerprint rows).
        $activeCleared = false;
        $warning = '';
        if ($activeUuid !== '' && $this->findByUuid($mdl->nodes->node, $activeUuid) == null) {
            $remapped = null;
            if ($activeFp !== null) {
                foreach ($mdl->nodes->node->iterateItems() as $nodeUuid => $node) {
                    if ($this->nodeFingerprint($node) === $activeFp) {
                        $remapped = $nodeUuid;
                        break;
                    }
                }
            }
            if ($remapped !== null) {
                $mdl->general->active_node = $remapped;
                $touched = true;
            } else {
                $mdl->general->active_node = '';
                $activeCleared = true;
                $warning = '活动节点已从订阅中消失，请重新选择活动节点并应用。';
            }
        }

        $mdl->serializeToConfig();
        \OPNsense\Core\Config::getInstance()->save();

        $result = [
            'result' => 'saved',
            'added' => $added,
            'updated' => $updated,
            'removed' => $removed,
            'skipped' => $skipped,
            'touched' => $touched,
            'reloaded' => false,
            'active_cleared' => $activeCleared,
        ];
        if ($warning !== '') {
            $result['warning'] = $warning;
        }

        // Conditional reload (P0-3): only when a config-referenced node
        // changed, and never when the active node was just cleared
        // (reloading with no active node would silently fall back to
        // freedom/direct). The running xray keeps the old config until
        // the user picks a new active node and applies.
        if ($touched && !$activeCleared) {
            $status = trim($backend->configdRun('xray status'));
            if (strpos($status, 'is running as pid') !== false) {
                $backend->configdpRun('template reload', ['OPNsense/Xray']);
                $gen = trim($backend->configdRun('xray generate_config'));
                if ($gen === 'OK') {
                    $backend->configdRun('xray restart');
                    $result['reloaded'] = true;
                } else {
                    $result['reload_error'] = '配置生成失败，未重启（旧配置仍在运行）。';
                }
            }
        }
        return $result;
    }

    /**
     * TCP ping test for nodes. Body: {uuids: [...]} or empty for all.
     */
    public function pingNodesAction()
    {
        if (!$this->request->isPost()) {
            return ['result' => 'failed'];
        }
        $uuids = $this->request->getPost('uuids');
        $mdl = $this->getModel();
        $targets = [];
        foreach ($mdl->nodes->node->iterateItems() as $nodeUuid => $node) {
            if (empty($uuids) || in_array($nodeUuid, (array)$uuids)) {
                $targets[] = ['uuid' => $nodeUuid, 'address' => (string)$node->address, 'port' => (string)$node->port];
            }
        }
        $backend = new Backend();
        $raw = $backend->configdpRun('xray ping_nodes', [json_encode($targets)]);
        $result = json_decode(trim($raw), true);
        return ['result' => 'ok', 'pings' => is_array($result) ? $result : []];
    }
}
