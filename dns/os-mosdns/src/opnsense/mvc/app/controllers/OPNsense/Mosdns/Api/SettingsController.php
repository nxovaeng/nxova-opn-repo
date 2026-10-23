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

    /* ---- rule groups (canonical plain-txt domain lists) ---- */

    public function searchGroupsAction()
    {
        return $this->searchBase('rulegroups');
    }

    /* the rules page shows local and remote groups as two separate grids;
       both live in the same rulegroups array, split by the source field */
    public function searchLocalGroupsAction()
    {
        return $this->searchBase('rulegroups', null, null, function ($record) {
            return (string)$record->source !== 'remote';
        });
    }

    public function searchRemoteGroupsAction()
    {
        return $this->searchBase('rulegroups', null, null, function ($record) {
            return (string)$record->source === 'remote';
        });
    }

    public function addLocalGroupAction()
    {
        return $this->addBase('group', 'rulegroups', ['source' => 'local']);
    }

    public function addRemoteGroupAction()
    {
        return $this->addBase('group', 'rulegroups', ['source' => 'remote']);
    }

    public function getGroupAction($uuid = null)
    {
        return $this->getBase('group', 'rulegroups', $uuid);
    }

    public function addGroupAction()
    {
        return $this->addBase('group', 'rulegroups');
    }

    public function setGroupAction($uuid)
    {
        return $this->setBase('group', 'rulegroups', $uuid);
    }

    public function delGroupAction($uuid)
    {
        $result = $this->delBase('rulegroups', $uuid);
        if (($result['result'] ?? '') !== 'failed') {
            // drop the group's content/cache files as well
            (new Backend())->configdpRun('mosdns rules delete_group', [$uuid]);
        }
        return $result;
    }

    public function toggleGroupAction($uuid, $enabled = null)
    {
        return $this->toggleBase('rulegroups', $uuid, $enabled);
    }
}
