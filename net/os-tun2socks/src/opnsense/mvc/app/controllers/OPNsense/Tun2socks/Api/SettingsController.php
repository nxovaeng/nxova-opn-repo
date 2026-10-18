<?php

/* Copyright (C) 2026 nxovaeng
 * All rights reserved.
 */

namespace OPNsense\Tun2socks\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

class SettingsController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'tun2socks';
    protected static $internalModelClass = '\OPNsense\Tun2socks\Tun2socks';
}
