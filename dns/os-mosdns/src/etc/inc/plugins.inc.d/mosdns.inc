<?php

/*
 * Copyright (C) 2026 nxovaeng
 * All rights reserved.
 */

function mosdns_services()
{
    $services = array();
    $services[] = array(
        'description' => gettext('MosDNS dynamic DNS forwarder'),
        'configd' => array(
            'restart' => array('mosdns restart'),
            'start' => array('mosdns start'),
            'stop' => array('mosdns stop'),
        ),
        'name' => 'mosdns',
        'pidfile' => '/var/run/mosdns.pid',
    );
    $services[] = array(
        'description' => gettext('pf-aliasd pf table sync daemon'),
        'configd' => array(
            'restart' => array('mosdns pfaliasd.restart'),
            'start' => array('mosdns pfaliasd.start'),
            'stop' => array('mosdns pfaliasd.stop'),
        ),
        'name' => 'pf_aliasd',
        'pidfile' => '/var/run/pf_aliasd.pid',
    );
    return $services;
}
