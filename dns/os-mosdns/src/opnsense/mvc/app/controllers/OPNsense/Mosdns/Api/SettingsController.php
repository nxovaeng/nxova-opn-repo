<?php

/* Copyright (C) 2026 nxovaeng
 * All rights reserved.
 */

namespace OPNsense\Mosdns\Api;

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Backend;

class SettingsController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'mosdns';
    protected static $internalModelClass = '\OPNsense\Mosdns\Mosdns';

    /* ---- rule groups (canonical plain-txt domain lists) ----
       One rulegroups array, split along two dimensions: source
       (local = custom content / remote = fetched from a URL) and type
       (direct / proxy / block). The rules page has one tab per type,
       each with a remote grid on top and a local grid below; both
       fields are forced server-side via search filters / add overlays,
       so the dialogs themselves carry neither field. */

    private function searchGroupsBy($source, $type)
    {
        return $this->searchBase('rulegroups.group', null, null, function ($record) use ($source, $type) {
            return (string)$record->source === $source && (string)$record->type === $type;
        });
    }

    private function addGroupBy($source, $type)
    {
        return $this->addBase('group', 'rulegroups.group', ['source' => $source, 'type' => $type]);
    }

    public function searchGroupsAction()
    {
        return $this->searchBase('rulegroups.group');
    }

    public function searchLocalDirectGroupsAction()
    {
        return $this->searchGroupsBy('local', 'direct');
    }

    public function searchLocalProxyGroupsAction()
    {
        return $this->searchGroupsBy('local', 'proxy');
    }

    public function searchLocalBlockGroupsAction()
    {
        return $this->searchGroupsBy('local', 'block');
    }

    public function searchRemoteDirectGroupsAction()
    {
        return $this->searchGroupsBy('remote', 'direct');
    }

    public function searchRemoteProxyGroupsAction()
    {
        return $this->searchGroupsBy('remote', 'proxy');
    }

    public function searchRemoteBlockGroupsAction()
    {
        return $this->searchGroupsBy('remote', 'block');
    }

    public function addLocalDirectGroupAction()
    {
        return $this->addGroupBy('local', 'direct');
    }

    public function addLocalProxyGroupAction()
    {
        return $this->addGroupBy('local', 'proxy');
    }

    public function addLocalBlockGroupAction()
    {
        return $this->addGroupBy('local', 'block');
    }

    public function addRemoteDirectGroupAction()
    {
        return $this->addGroupBy('remote', 'direct');
    }

    public function addRemoteProxyGroupAction()
    {
        return $this->addGroupBy('remote', 'proxy');
    }

    public function addRemoteBlockGroupAction()
    {
        return $this->addGroupBy('remote', 'block');
    }

    public function getGroupAction($uuid = null)
    {
        return $this->getBase('group', 'rulegroups.group', $uuid);
    }

    public function setGroupAction($uuid)
    {
        return $this->setBase('group', 'rulegroups.group', $uuid);
    }

    public function delGroupAction($uuid)
    {
        $result = $this->delBase('rulegroups.group', $uuid);
        if (($result['result'] ?? '') !== 'failed') {
            // drop the group's content/cache files as well
            (new Backend())->configdpRun('mosdns rules delete_group', [$uuid]);
        }
        return $result;
    }

    public function toggleGroupAction($uuid, $enabled = null)
    {
        return $this->toggleBase('rulegroups.group', $uuid, $enabled);
    }
}
