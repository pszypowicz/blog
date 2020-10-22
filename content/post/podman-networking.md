+++
date = "2020-10-22T15:09:54+01:00"
title = "Testing podman < 2.1.x rootless networking"
tags = ["podman", "linux", "containers"]
categories = ["linux"]
+++

# Podman Rootless container network (< 2.1.0 feature>)

That's just a very simple note of using podman 2.1.x feature, which is podman rootless networking.

For now, if you want to be able to communicate between 2 containers directly, you would have to create them in the pod.

You can now create a network and connect you containers to it.

Each container will get it's individual ip address in that network.

So to quickly test that, let's run http server in one container, and make a curl request from the second container.

```bash
$ podman network create cni-podman0
$ podman run --name --network cni-podman0 -dt httpd
$ podman inspect httpd | grep IPAddress
            "IPAddress": "",
                    "IPAddress": "10.88.2.12",
```

Now we should note the ip address of the container, and try to make a curl from the container connected to the same network.

```bash
$ podman pull curlimages/curl
$ podman run --network cni-podman0 curl -s http://10.88.2.12 --max-time 5
<html><body><h1>It works!</h1></body></html>
```

## Notes

- Each container in a network, will have it's own IP address. The communication over localhost would not work between 2 container. It's not the same a communication in a POD.
