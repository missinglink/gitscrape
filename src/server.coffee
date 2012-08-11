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
      io.sockets.emit 'client.users.index', index
      
  socket.on 'server.user.search', (username) ->
    redis.smembers 'users', (err,index) ->
      found = []
      for user in index
        if user.indexOf(username) == 0
          found.push user
        
      io.sockets.emit 'client.user.search', found

  socket.on 'server.user.info', (username) ->
    redis.hgetall util.format('user:%s', username), (err,user) ->
      io.sockets.emit 'client.user.info', user
      
  socket.on 'server.users.total', () ->
    redis.scard 'users', (err,count) ->
      io.sockets.emit 'client.users.total', count
      
  socket.on 'server.queue.total', () ->
    redis.scard 'queue:user:update', (err,count) ->
      io.sockets.emit 'client.queue.total', count

  socket.on 'server.queue.newentry', () ->
    redis.sdiff 'queue:user:update', 'users', (err,index) ->
      io.sockets.emit 'client.queue.newentry', index.length

  socket.on 'server.rate.limit', () ->
    request 'https://api.github.com/rate_limit', (error, response, body) ->
      if body?
        io.sockets.emit 'client.rate.limit', JSON.parse body