
require "colors"

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

## Helpers

getMap = (cb) =>
    client.getMappings (err, list) =>
        console.log(err) if err
        cb(err, list)

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
        cb(err, ip)

intIp = (cb) =>
    client.findGateway (err, gateway, ip) =>
        console.log(err) if err?
        cb(err, ip)

updateIp = (file, error, cb) =>
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
        extIp (err, ip) =>
            data =
                ippublic: ip
                portssh: 0
                error: {}
            if err
                data.error.ip = err
            if error
                data.error.port = error
            cc.post '/updateip', data, (err,res, body) =>
                console.log(body)
                if err or not body.success
                    cb(err)
                else
                    cb()
    else
        cb("Error: file doesn't exist")

updateRoute = (port, cb) =>
    getMap (err, list) =>
        found = false
        intIp (err, ip) =>
            if err?
                cb(err)
            else
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


## Commands

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
    .command("get-map-desc <desc>")
    .description("Display mapping with description <desc>")
    .action (desc) ->
        console.log("Display mapping with description #{desc}....")
        client.getMappings "description":desc, (err, res) =>
            console.log(err) if err?
            console.log(res)
            process.exit 0

program
    .command("get-map")
    .description("Display mapping")
    .action () ->
        console.log("get mapping ....")
        getMap (err, list) =>
            console.log(list)
            process.exit 0


program
    .command("external-ip")
    .description("Display external IP")
    .action () ->
        console.log("Recover external IP ....")
        extIp (err, ip) =>
            console.log(err) if err?
            console.log(ip) if ip?
            process.exit 0


program 
    .command("add-route <public> <private> <ttl> <description>")
    .description("Add route")
    .action (pub, priv, ttl, desc) ->
        console.log("Add route ....")
        portMap pub, priv, ttl, desc, (err) =>
            if err?
                console.log("Add route failed: #{err}")
            else
                console.log("Route successfully added")
            process.exit 0

program 
    .command("internal-ip")
    .description("Add route")
    .action () ->
        console.log("Recover internal IP ....")
        intIp (err, ip) =>
            console.log(err) if err?
            console.log(ip) if ip?
            process.exit 0


program 
    .command("remove-route <public> <private> <description>")
    .description("Remove route")
    .action (pub, priv, desc) ->
        # Retrive route
        getMap (err, list) =>
            if err
                console.log('Cannot retrieve routes')
                process.exit 1
            else
                found = false
                for item in list
                    if item.public.port is parseInt(pub) and item.private.port is parseInt(priv) and item.description is desc
                        found  = true
                        # Remove route
                        unportMap item, (err) =>
                            if err?
                                console.log(err) 
                            else
                                console.log('Route successfully removed')
                            process.exit 0
                if not found
                    console.log("Route not found")
                    process.exit 0

program
    .command("test-local-ttl <port> [debug]")
    .description("Test local")
    .action (port, debug) ->
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
        testServer.listen parseInt(port), "0.0.0.0"
        console.log("Mapping private port #{port} to public port 443 with ttl 60")
        portMap 443, parseInt(port), 60, "test1:digidisk", (err) =>
            if err
                console.log(err) 
                exit(testServer, false)
            else
                getMap (err, list) =>
                    found = false
                    for item in list
                        if item.public.port is 443
                            found = true
                            console.log(item)
                            if item.private.port isnt parseInt(port)
                                console.log 'Error: bad private port'.red
                                exit(testServer,item)
                            else if item.description isnt "test1:digidisk"
                                console.log 'Error: bad description'.red
                                exit(testServer,item)
                            else
                                console.log("Route has been correctly added")
                                console.log("Try to request with server with private port ...")
                                server = new Client("http://localhost:#{port}")
                                server.get '/', (err,res, body) =>
                                    if debug?
                                        console.log("body: #{JSON.stringify(body)}")
                                        console.log("err: #{err}")
                                    if not body or body.msg is not  'ok'
                                        console.log "Error: bad response".red
                                        exit(testServer,item)
                                    else
                                        console.log('... Ok')
                                        extIp (err, ip) =>
                                            console.log("Your public IP adress is : #{ip}")
                                            console.log("Try to request with server with public port ...")
                                            server = new Client("http://#{ip}:443")                   
                                            server.get '/', (err,res, body) =>
                                                if debug?
                                                    console.log("body: #{JSON.stringify(body)}")
                                                    console.log "err: #{err}".red
                                                if body.msg isnt 'ok'
                                                    console.log "Error: bad response".red
                                                    exit(testServer,item)
                                                else
                                                    console.log('... Ok')
                                                    console.log 'Test local with ttl 60 is correct !'.green
                                                    exit(testServer,item)
                    if not found
                        exit(testServer,false)

program
    .command("test-local <port> [debug]")
    .description("Test local")
    .action (port, debug) ->
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
        testServer.listen parseInt(port), "0.0.0.0"
        console.log("Mapping private port #{port} to public port 443 with ttl 0")
        portMap 443, parseInt(port), 0, "test1:digidisk", (err) =>
            if err
                console.log(err) 
                exit(testServer, false)
            else
                getMap (err, list) =>
                    found = false
                    for item in list
                        if item.public.port is 443
                            found = true
                            console.log(item)
                            if item.private.port isnt parseInt(port)
                                console.log 'Error: bad private port'.red
                                exit(testServer,item)
                            else if item.description isnt "test1:digidisk"
                                console.log 'Error: bad description'.red
                                exit(testServer,item)
                            else if item.ttl isnt 0
                                console.log 'Error: bad ttl'.red
                                exit(testServer,item)
                            else
                                console.log("Route has been correctly added")
                                if debug?
                                    console.log item
                                console.log("Try to request with server with private port ...")
                                server = new Client("http://localhost:#{port}")
                                server.get '/', (err,res, body) =>
                                    if debug?
                                        console.log("body: #{JSON.stringify(body)}")
                                        console.log("err: #{err}")
                                    if not body or body.msg is not  'ok'
                                        console.log "Error: bad response".red
                                        exit(testServer,item)
                                    else
                                        console.log('... Ok')
                                        extIp (err, ip) =>
                                            console.log("Your public IP adress is : #{ip}")
                                            console.log("Try to request with server with public port ...")
                                            server = new Client("http://#{ip}:443")                   
                                            server.get '/', (err,res, body) =>
                                                if debug?
                                                    console.log("body: #{JSON.stringify(body)}")
                                                    console.log "err: #{err}".red
                                                if body.msg isnt 'ok'
                                                    console.log "Error: bad response".red
                                                    exit(testServer,item)
                                                else
                                                    console.log('... Ok')
                                                    console.log 'Test local with ttl 0 is correct !'.green
                                                    exit(testServer,item)
                    if not found
                        exit(testServer,false)

program
    .command("test-ext-partA <port> [debug]")
    .description("Test 2 Part A")
    .action (port, debug) ->
        console.log('Start test server')
        testServer = fakeServer(msg: 'ok', 200)
        testServer.listen parseInt(port), "0.0.0.0"
        console.log("Mapping private port #{port} to public port 443 with ttl 60")
        portMap 443, parseInt(port), 0, "test1:digidisk", (err) =>
            if err
                console.log(err)
                testServer.close()
                process.exit 0
            else
                getMap (err, list) =>
                    found = false
                    for item in list
                        if item.public.port is 443
                            found = true
                            if item.private.port isnt parseInt(port)
                                console.log(item)
                                console.log 'Error: bad private port'.red
                                testServer.close()
                                process.exit 0
                            else if item.description isnt "test1:digidisk"
                                console.log(item)
                                console.log 'Error: bad description'.red
                                testServer.close()
                                process.exit 0
                            else if item.ttl isnt 0
                                console.log(item)
                                console.log 'Error: bad ttl'.red
                                testServer.close()
                                process.exit 0
                            else
                                console.log("Route has been correctly added")
                                if debug?
                                    console.log item
                                console.log("Try to request with server with private port ...")
                                server = new Client("http://localhost:#{port}")
                                server.get '/', (err,res, body) =>
                                    if debug?
                                        console.log("body: #{JSON.stringify(body)}")
                                        console.log("err: #{err}")
                                    if not body or body.msg is not 'ok'
                                        console.log "Error: bad response".red
                                        testServer.close()
                                        process.exit 0
                                    else
                                        console.log('... Ok')
                                        extIp (err, ip) =>
                                            console.log("Your public IP adress is : #{ip}")
                                            console.log("Can you try to request http://#{ip}:443 from exterior ....")
                                            console.log("Stop this program when you have finish your test and execute test2-partB to remove the route")

program
    .command("test-ext-partB <port> [debug]")
    .description("Test 2")
    .action (port, debug) ->
        getMap (err, list) =>
            found = false
            for item in list
                if item.public.port is 443
                    found = true
                    if item.private.port isnt parseInt(port)
                        console.log(item)
                        console.log 'Error: bad private port'.red
                        process.exit 0
                    else if item.description isnt "test1:digidisk"
                        console.log(item)
                        console.log 'Error: bad description'.red
                        process.exit 0
                    else if item.ttl isnt 0
                        console.log(item)
                        console.log 'Error: bad ttl'.red
                        process.exit 0
                    else
                        unportMap item, (err) =>
                            console.log "Route successfully removed".green
                            process.exit 0
            if not found
                console.log "Error: route not found".red
                process.exit 0




program 
    .command("update-ip <file>")
    .description("Update IP public to c&c with configuration in <file>")
    .action (file) ->
        if fs.existsSync file
            # Read configuration file
            config = {}
            confs = fs.readFileSync file, 'utf8'
            confs = confs.split('\n')
            for conf in confs
                conf = conf.split('=')
                if conf[0] and conf[1]?
                    config[conf[0]] = conf[1]
                else
                    console.log("Configuration file seems to have uncorrect syntax")
            console.log(config)
            # Create c&c client
            cc = new Client(config["c&c_url"])
            cc.setBasicAuth config.id, config.password
            # Recover external ip
            extIp (err, ip) =>
                if err
                    console.log("Cannot retrieve external IP")
                    console.log(err)
                else
                    # Update ip
                    data =
                        ippublic: ip
                        portssh: 0
                        error: 
                            "ip": err
                    cc.post '/updateip', data, (err,res, body) =>
                        if err or not body.success
                            console.log(err)
                            process.exit 1
                        else
                            console.log('IP successfully updated')
                            process.exit 0
        else
            console.log("Error: file doesn't exist")
            process.exit 1

program 
    .command("update-route <port>")
    .description("Update route from public port <port> to 443 with ttl 0 and description 'digidisk'")
    .action (port) ->
        getMap (err, list) =>
            if err
                console.log("Cannot retrieve routes")
                console.log(err)
                process.exit 1
            found = false
            intIp (err, ip) =>
                if err
                    console.log("Cannot retrieve internal IP")
                    console.log(err)
                    process.exit 1
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
    .command("update [file]")
    .description("Update route and IP public to c&c with configuration in <file>, by default file is /etc/cozy/cozy-routing.conf")
    .action (file) ->
        console.log('Update route ...')
        updateRoute 9104, (error) =>
            if error
                console.log(error)
            console.log('Update IP ...')
            if not file
                file = "/etc/cozy/cozy-routing.conf"
            updateIp file, error, (err) =>
                if err
                    console.log(err)
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