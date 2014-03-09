natUpnp = require('nat-upnp')
program = require 'commander'

client = natUpnp.createClient()
pkg = require '../package.json'
version = pkg.version
fs = require 'fs'
S = require 'string'
async = require 'async'
request = require('request-json')

program
  .version(version)
  .usage('<action> <app>')


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

updateIp = (config, port, error, cb) =>
    cc = request.newClient(config["c&c_url"])
    cc.setBasicAuth config.id, config.password
    extIp (err, ip) =>
        data =
            ippublic: ip
            portssh: port
        if err
            error.ip = err
        if Object.keys(error).length isnt 0
            data.error = error
        console.log(data)
        cc.post '/updateip', data, (err,res, body) =>
            console.log(body)
            if data.error
                cb(data.error)
            if err or not body.success
                cb(err)
            else
                cb(null)

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
                        if route.private.port is parseInt(port) and
                            route.private.host is ip and
                            (route.ttl > 86400 or route.ttl is 0)
                                # Route is correct and ttl > 1 day
                                console.log("Route already created")
                                cb()
                        else
                            console.log("An other route on 443 exist")
                            # Remove old route
                            console.log("Remove old route ...")
                            unportMap route, (error) =>
                                console.log("Create new route ...")
                                portMap 443, parseInt(port), 0, "digidisk", (err) =>
                                    if err
                                        # Create new route with ttl of 1 week
                                        portMap 443, parseInt(port), 604800, "digidisk", (err) =>
                                            if error
                                                cb(error)
                                            if err
                                                cb(err)
                                            else
                                                cb()
                                    else
                                        cb()
                if not found
                    console.log("Route creation")
                    portMap 443, parseInt(port), 0, "digidisk", (err) =>
                        if err
                            # Create new route with ttl of 7 days
                            portMap 443, parseInt(port), 604800, "digidisk", (err) =>
                                if err
                                    cb(err)
                                else
                                    cb()
                        else
                            cb()

updateSshPort = (config, cb) ->
    port = config.ssh_port
    getMap (err, list) =>
        found = false
        intIp (err, ip) =>
            if err?
                cb(err)
            else
                for route in list
                    if route.public.port is port
                        found = true
                        if route.private.host is ip and route.private.port is 22
                            if route.ttl > 86400 or route.ttl is 0
                                cb(null, port)
                            else
                                console.log("Remove old route ...")
                                unportMap route, (error) =>
                                    console.log("Add new route ...")
                                    # Create new route with ttl of 1 week
                                    portMap port, 22, 604800, "digidisk-ssh", (err) =>
                                        if error
                                            cb(error, port)
                                        if err
                                            cb(err, port)
                                        else
                                            cb(null, port)
                        else
                            updateSshPort(port+1, cb)
                if not found
                    # Create new route with ttl of 1 week
                    portMap port, 22, 0, "digidisk-ssh", (err) =>
                        if err
                            portMap port, 22, 604800, "digidisk-ssh", (err) =>
                                if err
                                    cb(err, port)
                                else
                                    cb(null, port)
                        else
                            cb(null, port)

## Basic function
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
    .command("internal-ip")
    .description("Display internal IP")
    .action () ->
        console.log("Recover internal IP ....")
        intIp (err, ip) =>
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
                    if item.public.port is parseInt(pub) and
                        item.private.port is parseInt(priv) and
                        item.description is desc
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

## Update route, ip and ssh port
program
    .command("update [file]")
    .description("Update route and IP public to c&c with configuration in <file>,"
        + "by default file is /etc/cozy/cozy-routing.conf")
    .action (file) ->
        error = {}
        if not file
            file = "/etc/cozy/cozy-routing.conf"
        if fs.existsSync file
            config = {}
            confs = fs.readFileSync file, 'utf8'
            confs = confs.split('\n')
            for conf in confs
                conf = conf.split('=')
                config[conf[0]] = conf[1]
            if config['c&c_url']? and config.id? and config.password? and config.ssh_port?
                console.log('Update route ...')
                updateRoute 443, (err) =>
                    if err
                        console.log("Error: #{err}")
                        error.port = err
                    console.log('Update IP ...')
                    updateSshPort config, (err, port) =>
                        if err
                            console.log("Error: #{err}")
                            error.ssh = err
                        updateIp config, port, error, (err) =>
                            if err
                                console.log("Error : ")
                                console.log(err)
                            else
                                console.log('Route and IP successfully updated')
                            process.exit 0
            else
                console.log('Error: bad configuration')
                if not config['c&c_url']?
                    console.log("c&c_url configuration doesn't exist")
                if not config.id?
                    console.log("id configuration doesn't exist")
                if not config.password?
                    console.log("password configuration doesn't exist")
                if not config.ssh_port?
                    console.log("ssh_port configuration doesn't exist")
                process.exit 1
        else
            console.log("Error: file doesn't exist")
            process.exit 1


## Clean digidisk routes
program
    .command("clean")
    .description("Clean Digidisk routes")
    .action () ->
        getMap (err, list) =>
            if err
                console.log(err)
            else
                count = 0
                async.eachSeries list, (route, cb) =>
                    if S(route.description).count('digidisk') is 1
                        count = count + 1
                        console.log("Remove route #{route.description} : ")
                        unportMap route, (err) =>
                            if err
                                console.log("    #{err}")
                            else
                                console.log "    Route successfully removed"
                            cb()
                    else
                        cb()
                , (err) =>
                    console.log("#{count} routes found")
                    process.exit 0

program
    .command("set-locale <locale>")
    .description("Change locale for locally installed Cozy.")
    .action (locale) ->
        client = request.newClient 'http://localhost:9103'
        client.post 'api/instance', locale: locale, (err, res, body) ->
            if err then console.log err
            else if res.statusCode isnt 200
                console.log 'Something went wrong while changing locale'
                console.log body
            else
                console.log "Locale set with #{locale}"
            process.exit 0

program
    .command("set-domain <domain>")
    .description("Change domain for locally installed Cozy.")
    .action (domain) ->
        client = request.newClient 'http://localhost:9103'
        client.post 'api/instance', domain: domain, (err, res, body) ->
            if err then console.log err
            else if res.statusCode isnt 200
                console.log 'Something went wrong while changing domain'
                console.log body
            else
                console.log "Domain set with #{domain}"
            process.exit 0

program
    .command("*")
    .description("Display error message for an unknown command.")
    .action ->
        console.log 'Unknown command, run "cozy-routing --help"' + \
                    ' to know the list of available commands.'
        process.exit 0

program.parse process.argv
