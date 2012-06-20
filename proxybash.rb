# ProxyBash, Bringing The World Through A Tight Hole

require 'gserver'
require 'timeout'
require 'thread'
require 'yaml'
# base64 used for proxy authentication, super secure
require 'base64'

module ProxyBash
	# ForwardThread, forwards data from one socket to another.
	# Used by both client and server.
	class ForwardThread < Thread
		def initialize(input, output)
			super() do
				until input.eof?
					output.write(input.read(1))
				end
				output.close
			end
		end
	end
	
	# Your outside man.
	class ProxyBashOutside < GServer
		def initialize(port=443, host='0.0.0.0', config='proxybash.yaml')
			@config = parse_config(config)
			super(port, host, Float::MAX, $stderr, true)
		end
		
		def serve(inside)
			# Some variables we'll be using
			server = ''
			port = 0
			
			timeout(5) do # Time is money, talk fast
				password = inside.gets.chomp
				if password != @config['password']
					inside.print "error. password incorrect.\n"
					return
				end
				server = inside.gets.chomp
				port = inside.gets.to_i
			end
			
			# Because ruby is so great, we don't really have to do any
			# error checking, but just for the hell of it, lets do something simple
			return if server.length < 3 or port == 0
			
			## Now we try to connect to the requested server
			begin
				outside = TCPSocket.new(server, port) 
			rescue
				inside.print "error.\n"
			else
				inside.print "connected.\n"
				in_to_out = ForwardThread.new(inside, outside);
				out_to_in = ForwardThread.new(outside, inside);
				in_to_out.join
				out_to_in.join
				puts "Stream ended"
			ensure
				outside.close
			end
		end
	end
	
	# Your inside man
	class ProxyBashInside < Thread
		def initialize(config='proxybash.yaml')
			@pipeholes = []
			@config = parse_config(config)
			@config['password'] = '' if @config['password'].nil?
			
			@config['pipeholes'].each do |pipehole|
				add_pipehole(pipehole['remotehost'], pipehole['remoteport'], pipehole['localport']).start(-1)
			end
			
			super() do
				for pipehole in @pipeholes
					pipehole.join
				end
			end
		end
		
		def add_pipehole(remotehost, remoteport, localport)
			@pipeholes << Pipehole.new(remotehost, remoteport, localport, @config)
			@pipeholes[-1]
		end
		
		# This runs on the inside and does the actual tunnelling
		class Pipehole < GServer	
			def initialize(remotehost, remoteport, localport, config)
				@config = config
				@remotehost = remotehost
				@remoteport = remoteport
				super(localport, @config['localhost'], Float::MAX, $stderr, true)
			end
			
			def serve(inside)
				begin
					if(@config['proxyhost'].nil?)
						outside = TCPSocket.new(@config['outsidehost'], @config['outsideport'])
					else
						outside = TCPSocket.new(@config['proxyhost'], @config['proxyport'])
					end
				rescue Exception => e
					puts "error: #{$!}"
					raise e
				else # Try and get past the proxy
					unless(@config['proxyhost'].nil?)
						begin
							outside.print("CONNECT #{@config['outsidehost']}:#{@config['outsideport']} HTTP/1.1\r\nProxy-Connection: keep-alive#{authentication()}\r\n\r\n")
							response = ""
							while response == ""
								response = outside.gets.strip 
							end
							if (response !~ /^HTTP\/1\.. 200/)
								raise "Unexpected reply from proxy, expecting 'HTTP/1.0 200 Connection established', got '#{response}'"
							end
						rescue Exception => e
							puts "error: #{e}"
							outside.close unless outside.eof?
							raise e
						end
					end
				end
				begin # Now we can send data to our outside server, so lets send the hostname and portnumber for our real endpoint:
					outside.print @config['password'] + "\n"
					outside.print @remotehost + "\n"
					outside.print @remoteport.to_s + "\n"
					response = ""
					while response == ""
						response = outside.gets.strip
					end
					if(response != "connected.")
						raise "ProxyBashOutside failed to connect to #{@remotehost}: #{response}"
					else # We are now connected to the real end point, and we can start tunneling data
						in_to_out = ForwardThread.new(inside, outside);
						out_to_in = ForwardThread.new(outside, inside);
						in_to_out.join
						out_to_in.join
					end
				rescue Exception => e
					puts "error: #{$!}"
					raise e
				ensure
					outside.close
				end
			end
		end
	end
	
	def authentication
	  if @config['proxyuser']
            auth = Base64::encode64(@config['proxyuser']+':'+@config['proxypass']).strip
	    return "\r\nProxy-Authorization: Basic #{auth}"
	  else return ''
    end
  end
	
	def parse_config(config_file)
		raise "File not found: " + config_file unless File.exists?(config_file)
		config_yaml = File.open(config_file).read
		YAML::load(config_yaml)
	end
end
