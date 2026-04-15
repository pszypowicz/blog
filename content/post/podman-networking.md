+++
title       = "Testing podman < 2.1.x rootless networking"
date        = "2020-10-22T15:09:54+01:00"
description = "A quick walkthrough of podman's 2.1.x rootless networking: create a CNI network, attach two containers, and hit one from the other."
tags        = ["podman", "linux", "containers"]
categories  = ["linux"]
+++

A quick note on podman 2.1.x rootless networking.

Until 2.1.0, to let two containers talk to each other directly, you had to put them in the same pod. From 2.1.0 onward you can create a network and attach containers to it, and each gets its own IP address on that network.

To test it: run an httpd container, then curl it from another container on the same network.

```bash
$ podman network create cni-podman0
$ podman run --name httpd --network cni-podman0 -dt httpd
$ podman inspect httpd | grep IPAddress
            "IPAddress": "",
                    "IPAddress": "10.88.2.12",
```

Note the IP, then curl it from a second container on the same network:

```bash
$ podman pull curlimages/curl
$ podman run --network cni-podman0 curl -s http://10.88.2.12 --max-time 5
<html><body><h1>It works!</h1></body></html>
```

## Notes

- Each container on a network gets its own IP. Communication over `localhost` does **not** work between two containers - that only applies inside a pod.
