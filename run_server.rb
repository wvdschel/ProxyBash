$LOAD_PATH.unshift Dir.pwd
require 'proxybash'

include ProxyBash

server = ProxyBashOutside.new(ARGV[0] || 443)
server.start(-1)
server.join
