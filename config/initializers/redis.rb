$redis = ENV['REDISCLOUD_URL'] ? Redis.new(url: ENV['REDISCLOUD_URL']) : Redis.new(port: 6379)
RubyBenchWeb::Application.config.cache_store = :redis_store, $redis.client.id
