natUpnp = require('nat-upnp');
program = require 'commander'
http = require('http')
client = natUpnp.createClient();
pkg = require '../package.json'
version = pkg.version
Client = require('request-json').JsonClient
#server = require '../test/server-test/server.coffee'



program
  .version(version)
  .usage('<action> <app>')

## Applications management ##

fakeServer = (json, code=200) ->

    lastCall = {}

    server = http.createServer (req, res) ->
        body = ""
        req.on 'data', (chunk) ->
            body += chunk
        req.on 'end', ->
            res.writeHead code, 'Content-Type': 'application/json'
            res.end(JSON.stringify json)
            data = JSON.parse body if body? and body.length > 0
            lastCall = request:req, body:data

    server.lastCall = -> lastCall
    server.reset = -> lastCall = {}
    return server


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


# Install
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
    .command("test-local [debug]")
    .description("Test 1")
    .action (debug) ->
        exit = (server, item) =>
            if item?
                console.log("Remove route")
                unportMap item, (err) =>
                    console.log("Stop server")
                    testServer.close()
                    process.exit 0
            else
                testServer.close()
                process.exit 0

        console.log('Start test server')  
        testServer = fakeServer(msg: 'ok', 200)
        testServer.listen 9105, "0.0.0.0"
        console.log("Mapping private port 9105 to public port 443 with ttl 0")
        portMap 443, 9105, 0, "test1:digidisk", (err) =>
            if err
                console.log(err) 
                exit(server,item)
            else
                getMap (list) =>
                    found = false
                    for item in list
                        if item.public.port is 443
                            found = true
                            if item.private.port isnt 9105
                                console.log('Error: bad private port')
                                console.log(item)
                                exit(server,item)
                            else if item.description isnt "test1:digidisk"
                                console.log('Error: bad description')
                                console.log(item)
                                exit(server,item)
                            else if item.ttl isnt 0
                                console.log('Eror: bad ttl')
                                console.log(item)
                                exit(server,item)
                            else
                                console.log("Route has been correctly added")
                                if debug?
                                    console.log item
                                console.log("Try to request with server with private port ...")
                                server = new Client('http://localhost:9105')
                                server.get '/', (err,res, body) =>
                                    if debug?
                                        console.log("body: #{JSON.stringify(body)}")
                                        console.log("err: #{err}")
                                    if body.msg is not  'ok'
                                        console.log("Error: bad response")
                                        exit(server,item)
                                    else
                                        console.log('... Ok')
                                        extIp (ip) =>
                                            console.log("Your public IP adress is : #{ip}")
                                            console.log("Try to request with server with public port ...")
                                            server = new Client("http://#{ip}:443")                   
                                            server.get '/', (err,res, body) =>
                                                if debug?
                                                    console.log("body: #{JSON.stringify(body)}")
                                                    console.log("err: #{err}")
                                                if body.msg isnt 'ok'
                                                    console.log("Error: bad response")
                                                    exit(server,item)
                                                else
                                                    console.log('... Ok')
                                                    console.log('Test 1 is correct !')
                                                    exit(server,item)
                    if not found
                        exit(server,false)

program
    .command("test-ext-partA [debug]")
    .description("Test 2 Part A")
    .action (debug) ->
        console.log('Start test server')  
        testServer = fakeServer(msg: 'ok', 200)
        testServer.listen 9105, "0.0.0.0"
        console.log("Mapping private port 9105 to public port 443 with ttl 60")
        portMap 443, 9105, 0, "test1:digidisk", (err) =>
            if err
                console.log(err) 
                testServer.close()
                process.exit 0
            else
                getMap (list) =>
                    found = false
                    for item in list
                        if item.public.port is 443
                            found = true
                            if item.private.port isnt 9105
                                console.log('Error: bad private port')
                                console.log(item)
                                testServer.close()
                                process.exit 0
                            else if item.description isnt "test1:digidisk"
                                console.log('Error: bad description')
                                console.log(item)
                                testServer.close()
                                process.exit 0
                            else if item.ttl isnt 0
                                console.log('Error: bad ttl')
                                console.log(item)
                                testServer.close()
                                process.exit 0
                            else
                                console.log("Route has been correctly added")
                                if debug?
                                    console.log item
                                console.log("Try to request with server with private port ...")
                                server = new Client('http://localhost:9105')
                                server.get '/', (err,res, body) =>
                                    if debug?
                                        console.log("body: #{JSON.stringify(body)}")
                                        console.log("err: #{err}")
                                    if body.msg is not  'ok'
                                        console.log("Error: bad response")
                                        testServer.close()
                                        process.exit 0
                                    else
                                        console.log('... Ok')
                                        extIp (ip) =>
                                            console.log("Your public IP adress is : #{ip}")
                                            console.log("Can you try to request http://#{ip}:443 from exterior ....")
                                            console.log("Stop this program when you have finish your test and execute test2-partB to remove the route")

program
    .command("test-ext-partB [debug]")
    .description("Test 2")
    .action (debug) ->
        getMap (list) =>
            found = false
            for item in list
                if item.public.port is 443
                    found = true
                    if item.private.port isnt 9105
                        console.log('Error: bad private port')
                        console.log(item)
                        process.exit 0
                    else if item.description isnt "test1:digidisk"
                        console.log('Error: bad description')
                        console.log(item)
                        process.exit 0
                    else if item.ttl isnt 0
                        console.log('Error: bad ttl')
                        console.log(item)
                        process.exit 0
                    else
                        unportMap item, (err) =>
                            console.log("Route successfully removed")
                            process.exit 0
            if not found
                console.log("Error: route not found")
                process.exit 0


program
    .command("*")
    .description("Display error message for an unknown command.")
    .action ->
        console.log 'Unknown command, run "cozy-monitor --help"' + \
                    ' to know the list of available commands.'

program.parse process.argv 