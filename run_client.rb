$LOAD_PATH.unshift Dir.pwd
require 'proxybash'

include ProxyBash

client = ProxyBashInside.new()
client.join
