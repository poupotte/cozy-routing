natUpnp = require('nat-upnp');
program = require 'commander'
client = natUpnp.createClient();
pkg = require '../package.json'
http = require 'http'
version = pkg.version
fs = require 'fs'
Client = require('request-json').JsonClient

program
  .version(version)
  .usage('<action> <app>')

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

intIp = (cb) =>
    client.findGateway (err, gateway, ip) =>
        console.log(err) if err?
        console.log(ip)
        cb(ip)

updateIp = (file, cb) =>
    if fs.existsSync file
        config = {}
        confs = fs.readFileSync file, 'utf8'
        confs = confs.split('\n')
        for conf in confs
            conf = conf.split('=')
            config[conf[0]] = conf[1]
        console.log(config)
        cc = new Client(config["c&c_url"])
        cc.setBasicAuth config.id, config.password
        extIp (ip) =>
            data =
                ippublic: ip
                portssh: 0
            cc.post '/updateip', data, (err,res, body) =>
                console.log(body)
                if err or not body.success
                    cb(err)
                else
                    cb()
    else
        cb("Error: file doesn't exist")

updateRoute = (port, cb) =>
    getMap (list) =>
        found = false
        intIp (ip) =>
            for route in list
                if route.public.port is 443
                    found = true
                    # A route exists
                    console.log(route)
                    if route.private.port is parseInt(port) and route.ttl is 0 and route.private.host is ip
                        # Route is correct
                        cb('Route already created')
                    else
                        console.log("An other route on 443 exist")
                        # Remove old route
                        console.log("Remove old route ...")
                        unportMap route, (err) =>
                            if err
                                cb(err)
                            else
                                # Create new route
                                console.log("Create new route ...")
                                portMap 443, parseInt(port), 0, "digidisk", (err) =>
                                    if err
                                        cb(err)
                                    else
                                        cb()
            if not found
                console.log("Route creation")
                # Create new route
                portMap 443, parseInt(port), 0, "digidisk", (err) =>
                    if err
                        cb(err)
                    else
                        cb()

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
        client.externalIp (err, ip) =>
            console.log(err) if err?
            console.log(ip)
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
    .command("internal-ip")
    .description("Add route")
    .action () ->
        client.findGateway (err, gateway, ip) =>
            console.log(err) if err?
            console.log(ip)
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
    .description("Test local")
    .action (debug) ->
        exit = (server, item) =>
            if item?
                console.log("Remove route")
                unportMap item, (err) =>
                    console.log("Stop server")
                    server.close()
                    process.exit 0
            else
                server.close()
                process.exit 0

        console.log('Start test server')  
        testServer = fakeServer(msg: 'ok', 200)
        testServer.listen 9105, "0.0.0.0"
        console.log("Mapping private port 9105 to public port 443 with ttl 0")
        portMap 443, 9105, 0, "test1:digidisk", (err) =>
            if err
                console.log(err) 
                exit(testServer, false)
            else
                getMap (list) =>
                    found = false
                    for item in list
                        if item.public.port is 443
                            found = true
                            if item.private.port isnt 9105
                                console.log('Error: bad private port')
                                console.log(item)
                                exit(testServer,item)
                            else if item.description isnt "test1:digidisk"
                                console.log('Error: bad description')
                                console.log(item)
                                exit(testServer,item)
                            else if item.ttl isnt 0
                                console.log('Eror: bad ttl')
                                console.log(item)
                                exit(testServer,item)
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
                                        exit(testServer,item)
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
                                                    exit(testServer,item)
                                                else
                                                    console.log('... Ok')
                                                    console.log('Test 1 is correct !')
                                                    exit(testServer,item)
                    if not found
                        exit(testServer,false)

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
                                    if body.msg is not 'ok'
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
    .command("update-ip <file>")
    .description("Update IP public")
    .action (file) ->
        if fs.existsSync file
            config = {}
            confs = fs.readFileSync file, 'utf8'
            confs = confs.split('\n')
            for conf in confs
                conf = conf.split('=')
                config[conf[0]] = conf[1]
            console.log(config)
            cc = new Client(config["c&c_url"])
            cc.setBasicAuth config.id, config.password
            extIp (ip) =>
                data =
                    ippublic: ip
                    portssh: 0
                cc.post '/updateip', data, (err,res, body) =>
                    console.log(err)
                    if err or not body.success
                        console.log(err)
                        process.exit 0
                    else
                        console.log('IP successfully updated')
                        process.exit 0

        else
            console.log("Error: file doesn't exist")
            process.exit 0

program 
    .command("update-route <port>")
    .description("Update route")
    .action (port) ->
        getMap (list) =>
            found = false
            intIp (ip) =>
                for route in list
                    if route.public.port is 443
                        found = true
                        # A route exists
                        console.log(route)
                        if route.private.port is parseInt(port) and route.ttl is 0 and route.private.ip is ip
                            # Route is correct
                            console.log('Route already created')
                            process.exit 0
                        else
                            console.log("An other route on 443 exist")
                            # Remove old route
                            console.log("Remove old route ...")
                            unportMap route, (err) =>
                                if err
                                    console.log(err)
                                    process.exit 0
                                else
                                    # Create new route
                                    console.log("Create new route ...")
                                    portMap 443, parseInt(port), 0, "digidisk", (err) =>
                                        if err
                                            console.log(err)
                                        else
                                            console.log("Route successfully added")
                                        process.exit 0
                if not found
                    console.log("Route creation")
                    # Create new route
                    portMap 443, parseInt(port), 0, "digidisk", (err) =>
                        if err
                            console.log(err)
                        else
                            console.log("Route successfully added")
                        process.exit 0

program 
    .command("update <file>")
    .description("Update route and IP public")
    .action (file) ->
        console.log('Update IP ...')
        updateIp file, (err) =>
            if err
                console.log(err)
                process.exit 0
            console.log('Update route ...')
            updateRoute 9104, (err) =>
                if err
                    console.log(err)
                    process.exit 0
                else
                    console.log('Route and IP successfully updated')
                    process.exit 0

program
    .command("*")
    .description("Display error message for an unknown command.")
    .action ->
        console.log 'Unknown command, run "cozy-monitor --help"' + \
                    ' to know the list of available commands.'

program.parse process.argv 