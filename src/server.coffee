express = require 'express'
request = require 'request'
util    = require 'util'
http    = require 'http'
websock = require 'socket.io'

# Configure Server
app     = express()
server  = http.createServer app
io      = websock.listen server


server.listen 3000

# Express Routes
app.use app.router
app.use '/', express.static __dirname + '/../public'

# Redis Setup
redis = require('redis').createClient()
redis.on 'error', (err) -> console.log err

# Web Sockets
io.sockets.on 'connection', (socket) ->

  socket.on 'server.users.add', (username) ->
    redis.sadd 'queue:user:update', username
    
  socket.on 'server.users.index', () ->
    redis.smembers 'users', (err,index) ->
      socket.emit 'client.users.index', index
      
  socket.on 'server.user.search', (username) ->
    redis.smembers 'users', (err,index) ->
      found = []
      for user in index
        if user.indexOf(username) == 0
          found.push user
        
      socket.emit 'client.user.search', found

  socket.on 'server.user.info', (username) ->
    redis.hgetall util.format('user:%s', username), (err,user) ->
      socket.emit 'client.user.info', user
        
# Send stats to clients
stats = () ->

  redis.scard 'users', (err,count) ->
    io.sockets.emit 'client.users.total', count

  redis.scard 'queue:user:update', (err,count) ->
    io.sockets.emit 'client.queue.total', count

  request 'https://api.github.com/rate_limit', (error, response, body) ->
    if body?
      io.sockets.emit 'client.rate.limit', JSON.parse body

setInterval stats, 500