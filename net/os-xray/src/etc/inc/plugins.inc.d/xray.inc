<?php

/* Copyright (C) 2026 nxovaeng
 * All rights reserved.
 */

function xray_services()
{
    $services = array();
    $services[] = array(
        'description' => gettext('Xray-core proxy engine (os-xray)'),
        'configd' => array(
            'restart' => array('xray restart'),
            'start' => array('xray start'),
            'stop' => array('xray stop'),
        ),
        'name' => 'xray_os',
        'pidfile' => '/var/run/xray_os.pid',
    );
    return $services;
}
