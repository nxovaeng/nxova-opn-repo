<?php

/*
 * Copyright (C) 2026 nxovaeng
 * All rights reserved.
 */

function tun2socks_services()
{
    $services = array();
    $services[] = array(
        'description' => gettext('tun2socks (hev-socks5-tunnel) daemon'),
        'configd' => array(
            'restart' => array('tun2socks restart'),
            'start' => array('tun2socks start'),
            'stop' => array('tun2socks stop'),
        ),
        'name' => 'tun2socks',
        'pidfile' => '/var/run/tun2socks.pid',
    );
    return $services;
}
