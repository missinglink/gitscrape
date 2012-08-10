# Configure Server
github = require 'octonode'
util = require 'util'

# Redis Setup
redis = require('redis').createClient()
redis.on 'error', (err) -> console.log err

# Github API
client = github.client()

# Worker
worker = () ->

  redis.spop 'queue:user:update', (err,username) ->
    if username?
    
      console.log util.format '[Processing Job]: %s', username
    
      # Skip locked records
      redis.get util.format('lock:user:%s',username), (err,lock) ->
        if lock? && lock == 'lock'
        
          # Put user back in the queue
#          console.log '[Record locked] - putting job back in queue'
#          redis.sadd 'queue:user:update', username
          
        else

          # Query user info
          user = client.user username
          user.info (err,data) ->

            if err?
            
              # Put user back in the queue
              console.log '[Service error - putting job back in queue]'
              redis.sadd 'queue:user:update', username

            # Save user
            else if data?.login
              redis.hmset util.format('user:%s',data.login), data, (err,reply) ->
              
                console.log '[User Saved]: %s', data.login
                redis.sadd 'users', data.login

                # Lock the user from update for 1 day
                redis.set util.format('lock:user:%s',data.login), 'lock'
                redis.expire util.format('lock:user:%s',data.login), 86400

              # Update followers & Queue follower users for download
              user.followers (err,users) ->

                followersKey = util.format 'user:%s:followers', data.login
                redis.del followersKey

                for user in users
                  if user?.login
                    redis.sadd followersKey, user.login
                    redis.sadd 'queue:user:update', user.login
                    console.log '[Added follower]: %s', user.login
                    
            else console.log '[Service returned invalid user record]'

    else console.log '[Nothing to do]'

#  process.nextTick worker

setInterval worker, 10