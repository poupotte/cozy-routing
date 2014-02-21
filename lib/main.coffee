natUpnp = require('nat-upnp');
program = require 'commander'
client = natUpnp.createClient();
pkg = require '../package.json'
version = pkg.version



program
  .version(version)
  .usage('<action> <app>')


getMap = (cb)=>
    client.getMappings (err, list) =>
        console.log(err) if err
        cb(list)

portMap = (pub, priv, ttl, desc, cb) =>
    doc =
        "public": parseInt(pub)
        "private": parseInt(priv)
        "ttl": parseInt(ttl) 
        "description": desc
    client.portMapping doc, (err) =>
        cb(err)

unportMap = (doc, cb) =>
    client.portUnmapping doc, (err) =>
        cb(err)

extIp = (cb) =>
     client.externalIp (err, ip) =>
        console.log(err) if err?
        cb(ip)

program
    .command("get-map-local")
    .description("Display local mapping")
    .action () ->
        console.log("Display local mapping ....")
        client.getMappings "local":true, (err, res) =>
            console.log(err) if err?
            console.log(res)
            process.exit 0

program
    .command("get-map")
    .description("Display mapping")
    .action () ->
        console.log("get mapping ....")
        client.getMappings (err, res) =>
            console.log(err) if err?
            console.log(res)
            process.exit 0


program
    .command("external-ip")
    .description("Display external IP")
    .action () ->
        console.log("Recover external IP ....")
        client.externalIp (err, res) =>
            console.log(err) if err?
            console.log(res)
            process.exit 0


program 
    .command("add-route <public> <private> <ttl>")
    .description("Add route")
    .action (pub, priv, ttl) ->
        console.log("Add route ....")
        doc =
            "public": parseInt(pub)
            "private": parseInt(priv)
            "ttl": parseInt(ttl)
        console.log(doc)
        client.portMapping doc, (err) =>
            console.log("Add route failed: #{err}") if err?
            console.log("Route successfully added")
            process.exit 0


program 
    .command("remove-route <public> <private> <desc>")
    .description("Remove route")
    .action (pub, priv, desc) ->
        getMap (list) =>
            found = false
            for item in list
                if item.public.port is parseInt(pub) and item.private.port is parseInt(priv) and item.description is desc
                    found  = true
                    unportMap item, (err) =>
                        if err?
                            console.log(err) 
                            process.exit 0
                        else
                            console.log('Route successfully removed')
                            process.exit 0
            if not found
                console.log("Route not found")
                process.exit 0

program
    .command("*")
    .description("Display error message for an unknown command.")
    .action ->
        console.log 'Unknown command, run "cozy-monitor --help"' + \
                    ' to know the list of available commands.'

program.parse process.argv 