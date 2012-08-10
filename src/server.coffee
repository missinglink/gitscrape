# Configure Server
express = require 'express'
request = require 'request'
github = require 'octonode'
events = require 'events'
util = require 'util'
app = express()
server = require('http').createServer app
io = require('socket.io').listen server
io.set('log level', false)
server.listen 3000

KEY_LOCK_USER = 'lock:user:%s'

# Express Routes
app.use app.router
app.use '/', express.static __dirname + '/../public'

# Redis Setup
redis = require('redis').createClient()
redis.on 'error', (err) -> console.log err

# Web Sockets
io.sockets.on 'connection', (socket) ->

  socket.on 'users.add', (username) ->
    redis.sadd 'queue:user:update', username
    
  socket.on 'users.index', () ->
    redis.smembers 'users', (err,index) ->
      io.sockets.emit 'users.index', index

  socket.on 'users.info', (username) ->
    redis.hgetall util.format('user:%s', username), (err,user) ->
      io.sockets.emit 'users.info', user

      
client = github.client()

# Worker
worker = () ->

  redis.spop 'queue:user:update', (err,username) ->
    if username?
    
      # Skip locked records
      lockKey = util.format KEY_LOCK_USER, username
      redis.get lockKey, (err,lock) ->
        if lock? && lock == 'lock'
        
          # Put user back in the queue
          redis.sadd 'queue:user:update', username
          
        else

          # Query user info
          user = client.user username
          user.info (err,data) ->

            console.log err
            console.log data

            # Save user
            if data?.login
              redis.hmset util.format('user:%s',data.login), data, (err,reply) ->
              
                console.log util.format '[user saved]: %s', data.login
                redis.sadd 'users', data.login

                # Lock the user from update for 1 day
                redis.set lockKey, 'lock'
                redis.expire lockKey, 86400

              # Update followers & Queue follower users for download
              user.followers (err,users) ->

                followersKey = util.format 'user:%s:followers', data.login
                redis.del followersKey

                for user in users
                  if user?.login
                    redis.sadd followersKey, user.login
                    redis.sadd 'queue:user:update', user.login
            
            # An error occurred
            #else
            
              # Put user back in the queue
              #redis.sadd 'queue:user:update', username
                     
                
  process.nextTick worker

worker()