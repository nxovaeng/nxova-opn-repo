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
        $result = $this->delBase('subscriptions.subscription', $uuid);
        if ($result['result'] != 'failed' && $sub != null) {
            foreach ($mdl->nodes->node->iterateItems() as $nodeUuid => $node) {
                if ((string)$node->sub_id == $uuid) {
                    $mdl->nodes->node->del($nodeUuid);
                }
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
     * Fetch a subscription URL, parse links, replace that subscription's nodes.
     * Body: {uuid: "..."}.
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
        // drop old nodes of this subscription
        foreach ($mdl->nodes->node->iterateItems() as $nodeUuid => $node) {
            if ((string)$node->sub_id == $uuid) {
                $mdl->nodes->node->del($nodeUuid);
            }
        }
        $added = 0;
        foreach ($nodes as $ndata) {
            $node = $mdl->nodes->node->add();
            $ndata['sub_id'] = $uuid;
            foreach (['tag', 'protocol', 'address', 'port', 'network', 'security', 'sni', 'path', 'user_id', 'password', 'ss_method', 'vmess_cipher', 'flow', 'alter_id', 'host', 'fingerprint', 'allow_insecure', 'public_key', 'short_id', 'spider_x', 'params', 'sub_id'] as $f) {
                if (isset($ndata[$f])) {
                    $node->$f = $ndata[$f];
                }
            }
            $added++;
        }
        $mdl->serializeToConfig();
        \OPNsense\Core\Config::getInstance()->save();
        return ['result' => 'saved', 'added' => $added];
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
